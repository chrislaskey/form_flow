defmodule Demo.Repo.Migrations.AddFormFlowV2 do
  use Ecto.Migration

  def up, do: FormFlow.Data.Migration.up(version: 2)

  # Rolling back returns FormFlow to schema version 1
  def down, do: FormFlow.Data.Migration.down(version: 2)
end
