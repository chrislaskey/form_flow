# Neo4j

FormFlow stores flow diagrams as a property graph in your SQL database —
Postgres or SQLite. A future extension will dual-write the same data to
[Neo4j](https://neo4j.com), so installations with complex or numerous flows
can run true graph queries. **The extension does not exist yet.** This guide
records the mapping the SQL schema was designed around, so nothing needs
migrating when it lands.

## The dual-write contract

The SQL schema follows one rule everywhere: **domain data lives in
`properties`; infrastructure keys are columns, copied into `properties`.**
That rule is what makes the Neo4j mapping mechanical:

  * A node's or relationship's `properties` column **is** its future Neo4j
    property map, byte for byte. The schemas keep the copies in sync — see
    `FormFlow.Data.Graph.Node` and `FormFlow.Data.Graph.Relationship`.
  * The columns additionally become *structural relationships* in Neo4j
    (below). Membership therefore appears in Neo4j twice — as a property and
    as a relationship. Both derive from the same column, so they cannot
    drift: the property is the fidelity contract, the relationship is the
    query accelerator.
  * Graph rows (`form_flow_graphs`) map wholesale to `:Graph` nodes, so their
    columns (`owner_graph_id`, `made_reusable_at`) need no properties copy.

## The mapping

Rule of thumb: anything that is the target of a reference must be a Neo4j
node, or the reference cannot be traversed. Subflow references and ownership
point at graphs — so graphs are nodes too.

| SQL | Neo4j |
|-----|-------|
| `form_flow_graph_nodes` row | node — `labels` column → labels, `properties` column → property map, verbatim |
| `form_flow_graph_relationships` row | relationship — `label` → type, `properties` → property map |
| `form_flow_graphs` row | `:Graph` node (id, `made_reusable_at`, timestamps as properties) |
| `nodes.graph_id` column | `(n)-[:IN]->(:Graph)` |
| `nodes.subflow_id` column | `(n)-[:EMBEDS]->(:Graph)` |
| `graphs.owner_graph_id` column | `(:Graph)-[:OWNED_BY]->(:Graph)` |

## Reserved relationship types

`IN`, `EMBEDS`, and `OWNED_BY` are FormFlow's structural vocabulary. User
data must not collide with them, so `FormFlow.Data.Graph.Relationship`
rejects them as relationship labels today — a changeset error, not a
convention — which means no data will need cleaning up when the dual-write
arrives.

## What the mapping buys

The queries that motivate a graph database become single patterns:

    // where is this reusable subflow used?
    MATCH (n)-[:EMBEDS]->(:Graph {id: $id})
    RETURN DISTINCT n.graph_id

    // flatten an entire nested flow, every subflow level, one query
    MATCH path = (:Graph {id: $root})<-[:IN]-(start)-[:CONNECTS_TO|EMBEDS|IN*]->(x)
    RETURN path

    // everything a root flow owns (the delete/garbage-collection set)
    MATCH (g:Graph)-[:OWNED_BY]->(:Graph {id: $root})
    RETURN g

The first and third are indexed one-hop traversals; the second is the query
that is genuinely painful in SQL (a recursive CTE joining three tables per
nesting level) and trivial here.
