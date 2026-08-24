defmodule FormFlow.Data.MigrationTest do
  use ExUnit.Case, async: false

  alias FormFlow.Data.Migration
  alias FormFlow.Test.FakeRepos.MigratedRepo
  alias FormFlow.Test.FakeRepos.MysqlRepo
  alias FormFlow.Test.FakeRepos.PostgresRepo
  alias FormFlow.Test.FakeRepos.SQLiteRepo

  setup do
    on_exit(fn ->
      Application.delete_env(:form_flow, :repo)
      Application.delete_env(:form_flow, :migrator)
    end)
  end

  describe "current_version/1" do
    test "reports the latest version for each supported adapter" do
      assert Migration.current_version(repo: PostgresRepo) == 4
      assert Migration.current_version(repo: SQLiteRepo) == 4
    end

    test "uses the configured repo when none is passed" do
      Application.put_env(:form_flow, :repo, PostgresRepo)

      assert Migration.current_version() == 4
    end
  end

  describe "migrated_version/1" do
    test "is zero when FormFlow has never migrated" do
      assert Migration.migrated_version(repo: PostgresRepo) == 0
    end

    test "reads the applied version" do
      assert Migration.migrated_version(repo: MigratedRepo) == 1
    end
  end

  describe "adapter dispatch" do
    test "raises a helpful error for unsupported adapters" do
      assert_raise ArgumentError, ~r/no migrations for the Ecto.Adapters.MyXQL adapter/, fn ->
        Migration.current_version(repo: MysqlRepo)
      end
    end

    test "honors a configured migrator over the adapter default" do
      Application.put_env(:form_flow, :migrator, FormFlow.Data.Migrations.SQLite)

      assert Migration.current_version(repo: MysqlRepo) == 4
    end
  end

  describe "repo resolution" do
    test "raises when there is no repo to migrate" do
      assert_raise ArgumentError, ~r/could not determine which repo/, fn ->
        Migration.migrated_version()
      end
    end
  end

  describe "option validation" do
    test "rejects versions outside the supported range" do
      assert_raise ArgumentError, ~r/expected :version to be between 1..4, got: 99/, fn ->
        Migration.up(repo: PostgresRepo, version: 99)
      end

      assert_raise ArgumentError, ~r/expected :version to be between/, fn ->
        Migration.down(repo: PostgresRepo, version: 0)
      end
    end

    test "rejects prefixes that are not plain identifiers" do
      assert_raise ArgumentError, ~r/expected :prefix to be a valid unquoted identifier/, fn ->
        Migration.up(repo: PostgresRepo, prefix: ~s(public"; drop table users; --))
      end
    end

    test "accepts an atom prefix" do
      # Fails later, on DDL outside of a migration — but the prefix is accepted
      assert_raise RuntimeError, ~r/could not find migration runner/, fn ->
        Migration.up(repo: PostgresRepo, prefix: :tenant_one)
      end
    end
  end

  describe "version modules" do
    test "each supported version maps to a module that exists" do
      for migrator <- [FormFlow.Data.Migrations.Postgres, FormFlow.Data.Migrations.SQLite],
          version <- migrator.initial_version()..migrator.current_version() do
        module = migrator.version_module(version)

        assert Code.ensure_loaded?(module), "#{inspect(module)} does not exist"
        assert function_exported?(module, :up, 1)
        assert function_exported?(module, :down, 1)
      end
    end
  end
end
