defmodule DemoWeb.DocsLive.DataModelingLive.SqlExamples do
  @moduledoc """
  The worked examples `DemoWeb.DocsLive.DataModelingLive` prints under the two
  diagrams: how a graph is stored in a relational database, and the three
  ways it can be read back out — joins, a recursive CTE, and a graph
  database — followed by the shape FormFlow settled on and why.

  The first four examples use a tiny made-up `nodes`/`edges` schema rather
  than FormFlow's tables. They are teaching material, and the point is the
  shape of the query, not the column list. The last example is the real
  thing, and names the functions that issue it — those names are what to
  check when this page and the library drift.

  The statements are held as strings rather than written into the template
  because HEEx reads `{` as interpolation, and both the SQL and the Cypher
  are full of braces. `blurb` and `note` are rendered as plain text, so
  they carry no markup.
  """

  @doc """
  The examples, in reading order: store the graph, then the three ways to
  follow it, then what FormFlow does.

  Each is `%{id:, title:, blurb:, sql:, note:}` — `blurb` sets the
  statement up, `note` is what to take away from it.
  """
  def all, do: [tables(), joins(), recursive_cte(), graph_database(), form_flow()]

  defp tables do
    %{
      id: "tables",
      title: "Storing a graph",
      blurb: """
      Storing a graph is the easy half. It is two tables and a foreign key:
      one table for the things, one table for the lines between them. Every
      example below runs against this.
      """,
      sql: """
      CREATE TABLE nodes (
        id   integer PRIMARY KEY,
        name text
      );

      CREATE TABLE edges (
        source_id integer REFERENCES nodes (id),
        target_id integer REFERENCES nodes (id)
      );

      -- start --> details --> payment --> confirm
      INSERT INTO nodes (id, name) VALUES
        (1, 'start'), (2, 'details'), (3, 'payment'), (4, 'confirm');

      INSERT INTO edges (source_id, target_id) VALUES
        (1, 2), (2, 3), (3, 4);
      """,
      note: """
      Nothing here is special to a graph. Any database can hold one, and writing a node or a line is a single insert.

      The interesting part is reading it back. As long as you only want to filter the graph — "which nodes are named payment?" — it stays a normal table. The moment you want to follow it — "what comes after start, and after that?" — you have a choice to make, and it is the same three choices every time.
      """
    }
  end

  defp joins do
    %{
      id: "joins",
      title: "Option one: joins",
      blurb: """
      Following one line is a join. Following two lines is two joins. If you
      know how deep you need to go, this is all you need.
      """,
      sql: """
      -- What comes two steps after 'start'?
      SELECT third.name
        FROM nodes AS first
        JOIN edges AS e1     ON e1.source_id = first.id
        JOIN nodes AS second ON second.id = e1.target_id
        JOIN edges AS e2     ON e2.source_id = second.id
        JOIN nodes AS third  ON third.id = e2.target_id
       WHERE first.name = 'start';

      -- payment
      """,
      note: """
      This is the fastest of the three options and the easiest to reason about. It is ordinary SQL: the indexes work, the query planner understands it, and you can add a WHERE clause anywhere.

      The catch is that the depth is baked into the statement. Going three steps means writing two more joins. And the question that has no fixed depth — "everything reachable from start" — cannot be written this way at all, because you do not know how many joins to write until you have already looked.

      That is the whole trade. Joins are the right tool when the depth is part of the question, and no help when it isn't.
      """
    }
  end

  defp recursive_cte do
    %{
      id: "recursive-cte",
      title: "Option two: a recursive CTE",
      blurb: """
      A recursive common table expression is SQL's answer to unknown depth.
      A query that refers to itself: start somewhere, then keep joining the
      results back onto the edges until nothing new comes back.
      """,
      sql: """
      -- Everything reachable from 'start', however deep.
      -- Both PostgreSQL and SQLite support this.
      WITH RECURSIVE reachable AS (
        -- Where to start
        SELECT id, name, 0 AS depth
          FROM nodes
         WHERE name = 'start'

        UNION ALL

        -- One more step out, applied to whatever the last step found
        SELECT n.id, n.name, r.depth + 1
          FROM reachable AS r
          JOIN edges AS e ON e.source_id = r.id
          JOIN nodes AS n ON n.id = e.target_id
         WHERE r.depth < 10
      )
      SELECT * FROM reachable;
      """,
      note: """
      One statement, any depth, one round trip to the database. This is the standard answer, and for most graph questions in SQL it is the right one.

      What you give up is control. The traversal is opaque: the planner walks whatever you told it to walk, and filtering part way down means putting the condition inside the recursive half of the query, where it is easy to get subtly wrong.

      Then there is that depth cap, which is doing a job it is not really qualified for. SQL has no memory of where it has been, so an edge that points back to an earlier node loops until the cap stops it — and a cap cannot tell a cycle apart from a graph that is honestly ten levels deep. There are better guards (an array of visited ids, or PostgreSQL's CYCLE clause), but they are more machinery, and the SQLite version is different from the PostgreSQL one.
      """
    }
  end

  defp graph_database do
    %{
      id: "graph-database",
      title: "Option three: a graph database",
      blurb: """
      The third option is to stop asking SQL. In a graph database, following
      lines is the primary operation rather than something assembled out of
      joins, and it shows in how the question is written.
      """,
      sql: """
      // The same question in Cypher, Neo4j's query language.
      // The '*' is the part SQL has no syntax for: follow this kind of
      // line any number of times.
      MATCH (start:Step {name: 'start'})-[:CONNECTS_TO*]->(reachable:Step)
      RETURN reachable;
      """,
      note: """
      Depth is a symbol in the pattern instead of a shape in the statement, cycles are handled by the engine, and a traversal costs roughly what it should: the engine hops from node to node rather than matching rows against an index each time. For a large or deep graph the difference is not small.

      The cost is operational, not syntactic. It is a second database. It has to be running, something has to write to both, and the two have to agree. And the rest of your data is still in SQL, so a graph query usually answers with a list of ids that you then go and look up in SQL anyway.

      That last point is worth sitting with, because it is what makes the combination workable: you do not have to move everything. Keep the graph in the graph database, keep the records in SQL, and let each answer the questions it is good at.
      """
    }
  end

  defp form_flow do
    %{
      id: "form-flow",
      title: "What FormFlow does",
      blurb: """
      FormFlow takes option one, pushed as far as it goes: no joins and no
      recursion in SQL at all. Reading one level of the graph is two indexed
      lookups on the same key, and the traversal happens in Elixir.
      """,
      sql: """
      -- One flow's nodes and lines. Two lookups on the same index, no join
      -- between them — the caller wants both lists whole.
      SELECT * FROM form_flow_template_flow_nodes         WHERE flow_id = '3f2c...';
      SELECT * FROM form_flow_template_flow_relationships WHERE flow_id = '3f2c...';
      """,
      note: """
      That pair is what FormFlow.Data.Templates.Flows.get/1 issues. When a node embeds a subflow, FormFlow.Data.Templates.Flows.resolve_tree/1 runs the pair again for that flow, carrying a set of the flow ids it has already visited, and assembles the tree as it goes.

      This works because of the size and shape of the data. A flow is tens of rows, not thousands, and templates are one or two levels deep in practice, so the extra round trips are cheap. In exchange you get an exact cycle guard instead of a depth cap — a flow that embeds one of its own ancestors resolves to nothing, while the same flow embedded twice side by side is correctly resolved at both positions, a distinction a depth cap cannot draw.

      The limit is honest enough: the round trips grow with the number of flows in the tree. A template with many subflows nested many levels deep is where this shape gets slow, and no amount of SQL tuning fixes it, because the recursion is not in the SQL.

      That is what the Neo4j mapping above is for. The day flows get big enough for it to matter, "everything reachable from here, filtered, in one hop" is a question to hand to option three.
      """
    }
  end
end
