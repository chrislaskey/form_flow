defmodule Demo.FormFlowDownloadsTest do
  @moduledoc """
  Exercises the download and print routes against a real database, a real
  router, and a real request — the whole path the library's own tests can't
  reach: a mounted route, a position resolved out of the URL, the pinned
  definition parsed, and a file coming back.

  What it holds the library to is that a download says the same thing the
  page it was started from says. The Show page renders the pinned definition
  filled in with the instance's `data`; so does the file, through the same
  `FormFlow.Web.Instances.Forms.Shared.resolve/1`. A test that only checked
  the bytes were a PDF would pass while the two drifted apart.
  """

  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Controllers.Downloads
  alias FormFlow.Web.Downloads.Token

  describe "the download route" do
    test "sends the answers as a PDF the browser saves", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      conn = get(conn, download_url(instance.id, [form.id]))

      assert response_content_type(conn, :pdf) =~ "application/pdf"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ ~s(filename="application-only.pdf")
      assert String.starts_with?(conn.resp_body, "%PDF-1.4")
    end

    test "the file carries the question as the definition asks it, and the answer", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      conn = get(conn, download_url(instance.id, [form.id]))

      assert conn.resp_body =~ "(Name) Tj"
      assert conn.resp_body =~ "(Ada Lovelace) Tj"
      assert conn.resp_body =~ "(Only) Tj"
      assert conn.resp_body =~ "(Application) Tj"
    end

    test "an in-progress form downloads what has been filled in so far", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      {:ok, _started} = Instances.Forms.update_status(instance, [form.id], :in_progress)

      conn = get(conn, download_url(instance.id, [form.id]))

      assert conn.status == 200
      assert conn.resp_body =~ "(Status: In progress) Tj"
    end
  end

  describe "the print route" do
    test "sends the same bytes, inline, so the browser opens rather than saves", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      downloaded = get(conn, download_url(instance.id, [form.id]))
      printed = get(conn, print_url(instance.id, [form.id]))

      assert [disposition] = get_resp_header(printed, "content-disposition")
      assert disposition =~ "inline"
      assert response_content_type(printed, :pdf) =~ "application/pdf"

      # The PDF's creation stamp is the only thing that differs between two
      # renders of one form
      assert scrub(printed.resp_body) == scrub(downloaded.resp_body)
    end
  end

  describe "what a download refuses" do
    test "a flow instance that does not exist", %{conn: conn} do
      conn = get(conn, download_url(Ecto.UUID.generate(), [Ecto.UUID.generate()]))

      assert conn.status == 404
      assert conn.resp_body =~ "This flow no longer exists."
    end

    test "a position nobody has opened — there are no answers to print", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()

      conn = get(conn, download_url(instance.id, [form.id]))

      assert conn.status == 404
      assert conn.resp_body =~ "hasn't been started yet"
    end

    test "a position the flow does not have", %{conn: conn} do
      %{instance: instance} = flow_of_one()

      conn = get(conn, download_url(instance.id, [Ecto.UUID.generate()]))

      assert conn.status == 404
    end
  end

  describe "a page with nothing to take away" do
    test "offers neither button, since there is no document to make", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()

      {:ok, view, _html} = live(conn, "/users/#{instance.id}/forms/#{form.id}")

      refute has_element?(view, "button[data-disposition]")
    end
  end

  describe "what the page offers" do
    test "two buttons wired to the hook that mints on click", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      {:ok, view, _html} = live(conn, "/users/#{instance.id}/forms/#{form.id}")

      assert has_element?(view, "button[data-disposition='download']", "Download PDF")
      assert has_element?(view, "button[data-disposition='print']", "Print")

      # The colocated hook is what turns those clicks into a minted URL
      assert has_element?(view, "[phx-hook$='.Downloads'] button[data-disposition='download']")
    end

    test "no static link, so a URL cannot outlive the page it was drawn on", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      {:ok, _view, html} = live(conn, "/users/#{instance.id}/forms/#{form.id}")

      refute html =~ Downloads.path() <> "?token="
    end

    test "nothing at all when the application has not said it serves downloads", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      configured = Application.get_env(:form_flow, :download_path)
      Application.delete_env(:form_flow, :download_path)
      on_exit(fn -> Application.put_env(:form_flow, :download_path, configured) end)

      {:ok, view, html} = live(conn, "/users/#{instance.id}/forms/#{form.id}")

      assert html =~ "Ada Lovelace"
      refute has_element?(view, "button[data-disposition]")
      refute html =~ "Download PDF"
    end
  end

  describe "the token's lifetime" do
    test "an expired token is refused, and says the fix is to click again", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      url = download_url(instance.id, [form.id])
      Application.put_env(:form_flow, :download_token_max_age, -1)
      on_exit(fn -> Application.delete_env(:form_flow, :download_token_max_age) end)

      conn = get(conn, url)

      assert conn.status == 403
      assert conn.resp_body =~ "expired"
    end

    test "the identity the page had reaches the document's context", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      assert get(conn, download_url(instance.id, [form.id])).status == 200
    end
  end

  # The URL the page's mint would produce, built the same way: the token is
  # the whole request, so a test that wants to fetch a download has to mint
  # one exactly as the click does.
  defp download_url(flow_instance_id, path), do: token_url(flow_instance_id, path, :download)
  defp print_url(flow_instance_id, path), do: token_url(flow_instance_id, path, :print)

  defp token_url(flow_instance_id, path, disposition) do
    token =
      Token.encode(DemoWeb.Endpoint, %{
        user_id: "demo-user",
        tenant_id: nil,
        perspectives: [],
        flow_instance_id: flow_instance_id,
        path: path,
        disposition: disposition
      })

    Downloads.form_path(Downloads.path(), token)
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  # The demo's own PDF stamp moves every render; everything else must match
  defp scrub(pdf), do: String.replace(pdf, ~r/\/CreationDate \(D:[^)]*\)/, "")

  defp flow_of_one do
    {:ok, flow} = Flows.create(%{name: "Application"})

    start = build_node(flow, ["Start"], "Start")
    only = build_node(flow, ["Form"], "Only", %{form_id: published_form("Only").id})

    edge(flow, start, only)

    {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

    %{flow: flow, instance: instance, form: only}
  end

  defp complete(instance, path, data) do
    {:ok, _opened} = Instances.Forms.update_status(instance, path, :in_progress)
    {:ok, completed} = Instances.Forms.update_status(instance, path, :completed, data: data)

    completed
  end

  defp build_node(flow, labels, label, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{flow_id: flow.id, labels: labels, properties: %{"data" => %{"label" => label}}},
        attrs
      )

    {:ok, node} = FormFlowRepo.insert(Flow.Node.changeset(%Flow.Node{}, attrs))

    node
  end

  defp edge(flow, source, target) do
    {:ok, _relationship} =
      FormFlowRepo.insert(
        Flow.Relationship.changeset(%Flow.Relationship{}, %{
          flow_id: flow.id,
          source_id: source.id,
          target_id: target.id,
          label: "CONNECTS_TO"
        })
      )
  end

  defp published_form(name) do
    {:ok, form} = Forms.create(%{name: "#{name} #{System.unique_integer([:positive])}"})

    [draft] = form.versions
    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}

    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    form
  end
end
