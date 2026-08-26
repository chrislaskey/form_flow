defmodule DemoWeb.Router do
  use DemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  import FormFlow.Web.Assets.Router

  scope "/" do
    form_flow_assets()
  end

  scope "/", DemoWeb do
    pipe_through :browser

    live "/install-check", InstallCheckLive
    live "/admin/*path", FormFlowLive.Admin
    live "/users/*path", FormFlowLive.Users
    live "/*path", ReadmeLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", DemoWeb do
  #   pipe_through :api
  # end
end
