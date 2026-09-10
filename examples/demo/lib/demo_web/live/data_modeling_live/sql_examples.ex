defmodule DemoWeb.DataModelingLive.SqlExamples do
  @moduledoc """
  The worked SQL `DemoWeb.DataModelingLive` prints under the two diagrams:
  how a flow's graph is written into a relational database, how it is read
  back, and the two shapes a read can take once it has to follow the graph.

  The statements are written by hand rather than captured from Ecto — they
  are the page's teaching material, so they are spelled the way a reader
  would type them, with the noise (`RETURNING`, parameter placeholders,
  every column) left out. What they describe is real: each one names the
  function in FormFlow that issues its equivalent, and those names are the
  thing to check when this page and the library drift.

  They are held as strings rather than written into the template because
  HEEx reads `{` as interpolation, and both the `jsonb` literals and the
  `text[]` literals are full of braces.
  """

  @doc """
  The examples, in reading order: read, write, count, recurse — the shape of
  the data before the mechanics of putting it there.

  Each is `%{id:, title:, blurb:, sql:, note:}` — `blurb` sets the statement
  up, `note` is what to take away from it.
  """
  def all, do: [read(), write(), count(), recurse()]

  defp write do
    %{
      id: "write",
      title: "Writing a node and a relationship",
      blurb: """
      A node (a *step*, in the product's words) is one row, and a relationship
      between two nodes is another. Nothing about the graph is special to the
      database: domain data goes in the `properties` jsonb column, and the
      columns beside it are the structure.
      """,
      sql: """
      -- A node. Its labels are a text[], its domain data a jsonb map, and
      -- id/flow_id/form_id/slug are the columns the database can index and
      -- constrain. Note that they appear twice: once as a column, once inside
      -- properties. That copy is deliberate — it is what makes properties the
      -- Neo4j property map byte for byte, where there are no columns to
      -- match on.
      INSERT INTO form_flow_template_flow_nodes
        (id, flow_id, form_id, slug, labels, properties, inserted_at, updated_at)
      VALUES
        ('9b41...', '3f2c...', '7e05...', 'dog-license/owner-details',
         '{Step}',
         '{"name": "Owner details", "id": "9b41...",
           "flow_id": "3f2c...", "form_id": "7e05..."}',
         now(), now());

      -- A relationship between two nodes. Its Neo4j type is the label column;
      -- a unique index on (source_id, target_id, label) is what stops the same
      -- pair being linked twice the same way.
      INSERT INTO form_flow_template_flow_relationships
        (id, flow_id, source_id, target_id, label, properties, inserted_at, updated_at)
      VALUES
        ('c7a2...', '3f2c...', '4d18...', '9b41...', 'CONNECTS_TO',
         '{"id": "c7a2...", "flow_id": "3f2c..."}', now(), now());
      """,
      note: """
      `FormFlow.Data.Templates.Flows.update/2` writes a whole flow this way,
      in one transaction: it deletes every node and relationship of the flow
      first and re-inserts the lot. Editing a diagram moves and rewires nodes
      wholesale, so replacing the rows is both simpler and cheaper than
      diffing them — and it is why nothing else in the schema may hold a
      foreign key to a node.
      """
    }
  end

  defp read do
    %{
      id: "read",
      title: "Reading one flow",
      blurb: """
      One level of the graph is two indexed lookups on the same key. There is
      no join between them: the nodes and the lines are assembled in the
      application, because the caller wants both lists whole.
      """,
      sql: """
      SELECT * FROM form_flow_template_flow_nodes         WHERE flow_id = '3f2c...';
      SELECT * FROM form_flow_template_flow_relationships WHERE flow_id = '3f2c...';
      """,
      note: """
      This is what `Repo.preload(flow, [:relationships, nodes: [:subflow, :form]])`
      issues inside `FormFlow.Data.Templates.Flows.get/1`. Both use the
      `flow_id` index, and both return a whole flow's worth of rows — tens,
      not thousands — which is the size the rest of the design assumes.
      """
    }
  end

  defp count do
    %{
      id: "count",
      title: "Counting: a joined subquery, not a correlated one",
      blurb: """
      The flows index shows how many nodes and relationships each flow has.
      There are two ways to ask, and the difference is not only speed.
      """,
      sql: """
      -- What FormFlow issues. Each child table is aggregated once, in its own
      -- derived table, then joined 1:1.
      SELECT f.*, COALESCE(nc.count, 0) AS nodes, COALESCE(rc.count, 0) AS relationships
      FROM form_flow_template_flows AS f
      LEFT JOIN (SELECT flow_id, count(id) AS count
                   FROM form_flow_template_flow_nodes
                  GROUP BY flow_id) AS nc ON nc.flow_id = f.id
      LEFT JOIN (SELECT flow_id, count(id) AS count
                   FROM form_flow_template_flow_relationships
                  GROUP BY flow_id) AS rc ON rc.flow_id = f.id
      WHERE f.owner_flow_id IS NULL
      ORDER BY f.inserted_at
      LIMIT 25;

      -- The correlated alternative. Reads better, and runs the two lookups
      -- again for every row the outer query returns.
      SELECT f.*,
             (SELECT count(*) FROM form_flow_template_flow_nodes n
               WHERE n.flow_id = f.id) AS nodes,
             (SELECT count(*) FROM form_flow_template_flow_relationships r
               WHERE r.flow_id = f.id) AS relationships
      FROM form_flow_template_flows AS f
      WHERE f.owner_flow_id IS NULL;
      """,
      note: """
      At 25 rows a page the speed difference is small — the correlated form
      does 50 index lookups, all of them cheap. It grows with the result set
      where the joined form does not, since each `GROUP BY` scans its table
      once however many flows come back. The reason FormFlow uses the joined
      form is the other one: it leaves the *outer* query ungrouped, so
      `FormFlow.Data.Templates.Flows.roots_query/1` can hand the query to a
      caller who then layers `ORDER BY`, `LIMIT`/`OFFSET`, and
      `Repo.aggregate(:count)` on top without fighting a `GROUP BY` that is
      not theirs.
      """
    }
  end

  defp recurse do
    %{
      id: "recurse",
      title: "Following the graph: a recursive CTE",
      blurb: """
      A node can embed a whole other flow, and that flow's nodes can embed
      more. Flattening every level is the query relational databases make you
      work for — and the one FormFlow deliberately does not write.
      """,
      sql: """
      -- Every node of a flow and of everything it embeds, one round trip.
      -- Both Postgres and SQLite support this.
      WITH RECURSIVE tree AS (
        SELECT id, flow_id, subflow_id, 0 AS depth
          FROM form_flow_template_flow_nodes
         WHERE flow_id = '3f2c...'

        UNION ALL

        SELECT child.id, child.flow_id, child.subflow_id, parent.depth + 1
          FROM form_flow_template_flow_nodes AS child
          JOIN tree AS parent ON child.flow_id = parent.subflow_id
         WHERE parent.depth < 10
      )
      SELECT * FROM tree;
      """,
      note: """
      One statement, any depth — and a `depth` cap doing the work a real
      cycle check should. SQL has no memory of where it has been, so a flow
      that embeds an ancestor recurses until the cap stops it, and the cap
      cannot tell that apart from a legitimately deep flow.

      `FormFlow.Data.Templates.Flows.resolve_tree/1` recurses in Elixir
      instead: one pair of the indexed lookups above per *flow* level, with a
      `MapSet` of flow ids already visited. That costs a round trip per level
      — one or two in practice — and buys an exact cycle guard, plus the
      distinction a depth cap cannot draw: a flow embedded twice as a sibling
      is resolved at both positions, while a flow that embeds an ancestor
      resolves to nothing.

      Neither shape is good at "flatten every level, filtered, in one hop".
      That query is the one a graph database answers in a single pattern, and
      it is the reason the Neo4j mapping above exists.
      """
    }
  end
end
