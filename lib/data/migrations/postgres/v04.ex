defmodule FormFlow.Data.Migrations.Postgres.V04 do
  @moduledoc false

  # Names and declared flavor for graphs.
  #
  #   * `name` — the human name shown in listings, breadcrumbs, and the
  #     reusable catalog. Nullable; the UI falls back to "Untitled".
  #   * `label` — the graph's declared flavor: "forms" (contains form steps)
  #     or "subflows" (contains subflow steps), never mixed. Declared at
  #     creation and immutable after. Named `label` to mirror Neo4j, where it
  #     becomes the second label on the `:Graph` node (:Graph:Forms /
  #     :Graph:Subflows). Existing graphs backfill as "forms".
  #
  # The SQLite version of this file is intentionally a near-copy — see V01.

  use Ecto.Migration

  def up(context) do
    alter table(:form_flow_graphs, prefix: context.prefix) do
      add_if_not_exists(:name, :string)
      add_if_not_exists(:label, :string, null: false, default: "forms")
    end
  end

  def down(context) do
    alter table(:form_flow_graphs, prefix: context.prefix) do
      remove(:label)
      remove(:name)
    end
  end
end
