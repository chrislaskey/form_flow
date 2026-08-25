defmodule FormFlow.Web.Templates.Forms.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Index` LiveComponent lists the form catalog.

  A plain table of the reusable forms `FormFlow.Data.Templates.Forms.list/1`
  returns — owned forms live inside their flow trees and are reached by
  drill-in, never listed here.

      <.live_component module={FormFlow.Web.Templates.Forms.Index} id="forms-index" />

  `base` is the path prefix the forms pages are mounted under, used to build
  the links — with the default `""`, rows link to `/forms/:id`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Forms

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:app, fn -> "default" end)

    {:ok, assign(socket, :forms, Forms.list(socket.assigns.app))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <h2 class="text-sm font-semibold">Forms</h2>
        <.link
          navigate={"#{@base}/forms/new"}
          class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
        >
          New form
        </.link>
      </div>

      <p :if={@forms == []} class="text-sm text-zinc-500">
        No forms yet — create the first one.
      </p>

      <table :if={@forms != []} class="w-full text-left text-sm">
        <thead>
          <tr class="border-b border-zinc-300 text-xs text-zinc-500">
            <th class="py-2 pr-4 font-medium">Name</th>
            <th class="py-2 pr-4 font-medium">Description</th>
            <th class="py-2 pr-4 font-medium">Created</th>
            <th class="py-2 font-medium"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={form <- @forms} class="border-b border-zinc-200">
            <td class="py-2 pr-4">
              <.link navigate={"#{@base}/forms/#{form.id}"} class="hover:underline">
                {form.name}
              </.link>
              <span class="block font-mono text-[10px] text-zinc-400">{form.id}</span>
            </td>
            <td class="py-2 pr-4 text-xs text-zinc-500">{form.description}</td>
            <td class="py-2 pr-4 text-xs text-zinc-500">
              {Calendar.strftime(form.inserted_at, "%Y-%m-%d %H:%M")}
            </td>
            <td class="py-2 text-right whitespace-nowrap">
              <.link navigate={"#{@base}/forms/#{form.id}"} class="text-cyan-600 hover:underline">
                Show
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
