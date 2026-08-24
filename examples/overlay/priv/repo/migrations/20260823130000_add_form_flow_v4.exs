defmodule Demo.Repo.Migrations.AddFormFlowV4 do
  use Ecto.Migration

  def up, do: FormFlow.Data.Migration.up(version: 4)

  # Rolling back returns FormFlow to schema version 3
  def down, do: FormFlow.Data.Migration.down(version: 4)
end
