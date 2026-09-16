# FormFlow

> Batteries included library for creating dynamic form-based user flows in Phoenix.
> Use drag-and-drop UIs to build complex user journeys. Reliable, verifiable,
> and deterministic results.

<p align="center">
  <img title="v0.26.0 Overview Screenshot" src="https://raw.githubusercontent.com/chrislaskey/form_flow/refs/heads/main/examples/screenshot-overview-v0.26.0.gif" width="1200">
</p>

## Why FormFlow?

Web apps are great for building forms. Creating an individual form in code is
easier than ever, especially using LLM based tools. **But there's a problem**.
The more complex the flow gets, the harder and harder it is to maintain and
ensure things are working correctly for users as they move from one flow to the
next.

FormFlow solves this problem by approaching things differently. Rather than
creating forms as code, it writes **forms as data**. In fact, the library stores
the entire journey (which we call the flow) in data.

Using data also means it is easy to change. With drag-and-drop
functionality, FormFlow makes it fast to get started building flows.
But more importantly, it **stays easy to manage even as the complexity grows**
across multiple forms, multiple user types, and beyond.

The best part about data is it's much easier to check for potential
issues that cause problems for users. And by using data, we can be certain all
the forms and flows are work consistently using the same rules no matter
how complex the business case is you're tackling.

FormFlow has a built-in health check that makes it easy to spot potential
issues before it reaches users:

<p align="center">
  <img title="v0.26.0 Health Screenshot" src="https://raw.githubusercontent.com/chrislaskey/form_flow/refs/heads/main/examples/screenshot-health-v0.26.0.gif" width="1200">
</p>

## How easy is it to customize?

Storing flows and forms in data means everything is stable and consistent. It's
great for things to be uniform, but what if you need to customize something?
This is a common problem, and often times data-driven systems are rigid.

When creating FormFlow, true, easy to use, flexible **customization is built into
the core of it's design**, and not an afterthought.

Almost everything is customizable, from the flow logic to the detailed
rendering. All of it is customized using standard Elixir and Phoenix code.
No macro DSL language to learn. Simple changes can be done by with
well-documented component attributes. More complex customization can be done by
passing Elixir modules with custom callback implementations.

Nothing's worse than a library that doesn't feel like a part of the existing
app. So when it comes to UI/UX, it supports your existing applications
CoreComponents, so everything from icons to error states in field inputs is
native to your app.

## How do I use it?

FormFlow is built as an Elixir library. It's compatible with any modern 
Phoenix LiveView application. It supports both **SQLite and PostgreSQL** for the
database layer. While not required, it also has **optional Neo4J** graph
database support for that makes it even more efficient, especially for complex
workflows.

If you have an existing Phoenix LiveView application, it's easy to install the
library as a mix.exs dependency and fits into the existing application.

If you don't use Phoenix for your main app, don't worry! FormFlow can be
deployed as a standalone app by wrapping it in Phoenix.

## How is FormFlow built?

Modern software engineering is undergoing an evolution. At the time of writing,
as an industry we're all exploring the best ways to use and not use LLMs. This library
is one exploration of those ideas - **human firmly in the loop accelerated by
the LLM tools**, ensuring code is properly architected but not handwriting every line.

The goal is to speed up classic software engineering lifecycle, not
to replace it. More than just a "human (somewhere) in the loop", I am in
proverbial driver's seat, acting as both the software architect and product
designer, making important decisions and deciding the right path forward.

I then use LLMs to assist in completing the work and as well as helping
identify gaps in our plans. Documentation meant for humans is always hand
written by me, a fellow human.

## Licensing

Licensing is still to be determined, as the library is actively being built.
For now it's all rights reserved. So I would not recommend building a business
on top of it without talking to me first. For now code is available to
reference, but not for reuse. See LICENSE.md for specifics.
