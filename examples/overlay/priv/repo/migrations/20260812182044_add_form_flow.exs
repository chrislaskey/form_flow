defmodule Demo.Repo.Migrations.AddFormFlow do
  use Ecto.Migration

  def up, do: FormFlow.Data.Migration.up(version: 1)

  # Rolling back removes FormFlow's tables, and the data in them
  def down, do: FormFlow.Data.Migration.down(version: 1)
end
