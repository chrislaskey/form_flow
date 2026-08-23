defmodule Demo.Repo.Migrations.AddFormFlowV3 do
  use Ecto.Migration

  def up, do: FormFlow.Data.Migration.up(version: 3)

  # Rolling back returns FormFlow to schema version 2
  def down, do: FormFlow.Data.Migration.down(version: 3)
end
