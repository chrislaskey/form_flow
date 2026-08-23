defmodule FormFlow.Data.Migrations.Postgres do
  @moduledoc false

  # Postgres migrations, one module per version. See FormFlow.Data.Migration for
  # the host-facing API.

  @behaviour FormFlow.Data.Migration

  @initial_version 1
  @current_version 3

  @impl FormFlow.Data.Migration
  def initial_version, do: @initial_version

  @impl FormFlow.Data.Migration
  def current_version, do: @current_version

  @impl FormFlow.Data.Migration
  def version_module(version) when version in @initial_version..@current_version do
    Module.concat(__MODULE__, "V" <> String.pad_leading(to_string(version), 2, "0"))
  end
end
