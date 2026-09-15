# FormFlow

> Batteries included library for creating dynamic form-based user flows in Phoenix.
> Use drag-and-drop UIs to build complex user journeys. Reliable, verifiable,
> and deterministic results.

## Why FormFlow?

Web apps are great for building forms. Creating an individual form in code is
easier than ever, especially using LLM based tools. **But there's a problem**.
The more complex the flow gets, the harder and harder it is to maintain and
ensure things are working correctly for users as they move from one flow to the
next.

FormFlow solves this problem by approaching things differently. Rather than
creating forms as code, it writes **forms as data**. In fact, the library stores
the entire journey (which we call the flow) in data.

The nice thing about data is it's much easier to check for potential
issues that cause problems for users. And by using data, we can be certain all
the forms and flows are work consistently using the same rules no matter
how complex the business case is you're tackling.

Using data also means it is easy to change. With drag-and-drop
functionality, FormFlow makes it fast to get started building flows.
But more importantly, it **stays easy to manage even as the complexity grows**
across multiple forms, multiple user types, and beyond.

## Data-driven systems are hard to customize, right?

Storing flows and forms in data means everything is stable and consistent. It's
great for things to be uniform, but what if you need to customize something?

This is a common problem, and often times data derived systems are rigid.

So when building FormFlow, true, easy to use, flexible customization is built into
the core of it's design, and not an afterthought.

Almost everything is customizable, from the flow logic to the detailed
rendering. All of it is done using standard Elixir code. No macro DSL language
to learn. No hooks to memorize. Simple changes can be done by passing component
attributes. More complex things can be done by passing Elixir modules with
custom implementations.

When it comes to UI/UX, it supports using your applications CoreComponents, so
everything from icons to error states in field inputs is native to your app.

## How do I use it?

FormFlow is built as an Elixir library. It's compatible with any modern 
Phoenix LiveView application. It supports both SQLite and PostgreSQL for the
database layer. While not required, it also has optional support for
Neo4J that makes it even more efficient, especially for complex workflows.

If you have an existing Phoenix LiveView application, it's easy to install as
a dependency and click immediately into the existing application.

If you don't use Phoenix for your main app, don't worry! FormFlow can be
deployed as a standalone app easily.

## Licensing

Licensing is still to be determined, as the library is actively being built.
For now it's all rights reserved. So I would not recommend building a business
on top of it without talking to me first. For now code is available to
reference, but not for reuse. See LICENSE.md for specifics.
