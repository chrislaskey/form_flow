# Form Flow

> Batteries included library for creating dynamic form-based user flows in Phoenix.
> Use drag-and-drop UIs to build complex user journeys. Reliable, verifiable,
> and deterministic results.

## Why Form Flow?

Web apps are great for building forms. Coding an individual form is easier
than ever, especially using LLM based tools. But the more complex the flow
gets, the harder and harder it is to maintain and ensure things are working
correctly for users as they move from one flow to the next.

Form Flow solves this problem by approaching things differently. Rather than
creating forms as code, it writes **forms as data**. In fact, the library stores
the entire journey (which we call the flow) in data.

The nice thing about data is it's much easier to check for potential
issues that cause problems for users. And by using data, we can be certain all
the forms and flows are rendered consistently using the same rules no matter
how complex the business case is you're tackling.

Another nice thing about data is it can be easily change. With drag-and-drop
functionality, Form Flow makes it fast to get started building flows.
But more importantly, it stays easy to manage even as the complexity grows
across multiple forms, multiple user types, and beyond.

## How do I use it?

Form Flow is built as an Elixir library. It's compatible with any modern 
Phoenix LiveView application. It supports both SQLite and PostgreSQL for the
database layer. While not required, it also has optional support for
Neo4J that makes it even more efficient, especially for complex workflows.

If you have an existing Phoenix LiveView application, it's easy to install as
a dependency and click immediately into the existing application.

If you don't use Phoenix for your main app, don't worry! Form Flow can be
deployed as a standalone app easily.

See the guides and demo apps for examples.
