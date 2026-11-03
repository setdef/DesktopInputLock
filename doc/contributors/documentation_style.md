<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Documentation Style Guide

This project follows a strict and specific documentation style designed to be helpful, readable, and consistent. It combines the structural clarity of Christopher Alexander's Pattern Language with the prose style of William Zinsser's *On Writing Well* and the usability of the U.S. Federal Plain Language Guidelines.

**All agents and contributors must adhere to these standards.**

## 1. Core Philosophy

*   **Context, Problem, Solution (Alexandrian Form):** Do not just say *what* a class does. Explain *why* it exists. Start with the context, state the problem (the pain point without this tool), and then present the class as the solution.
*   **Prose Style (Zinsser/Klinkenborg):** Use short, punchy sentences. Use active voice. Cut unnecessary words. Avoid "allow," "enable," "provide," "support," "functionality," and "capability" where possible. Weak verbs hide the action. Strong verbs drive the sentence.
*   **User-Centric (Plain Language):** Speak directly to the user ("You"). Don't abstract them away ("The developer"). Focus on their goals and how this tool helps them achieve those goals.
*   **Tone (Supportive and Authoritative, not Hostile or Prescriptive):** Avoid "must," "requires," "need to," or "mandatory." These words sound bossy. Treat the user as a capable peer. Instead of "You must do X," use imperative "Do X" or cause-and-effect "X ensures Y."

## 2. Class Documentation

Every public class must begin with a **Context-Problem-Solution** narrative.

### Structure

1.  **Summary Line:** A single line explaining the class's role.
2.  **Context (Narrative):** A short paragraph establishing the domain or situation.
3.  **Problem (Narrative):** A sentence or two identifying the specific difficulty, complexity, or "pain" the user faces in this context without the class.
4.  **Solution (Narrative):** A sentence explaining how this class solves that problem, often starting with "This class..." or "Use it to...".
5.  **Usage (Narrative):** A concrete "Use it to..." sentence listing common applications.
6.  **Example:** A comprehensive, copy-pasteable code example using `=== Examples`. Provide **multiple** examples to cover different use cases (e.g., basic usage vs. advanced configuration).

### Example

**Bad (Generic/Descriptive):**
<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2025 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
# A class for managing resources.
# It allows the user to store objects by integer ID.
# Supports adding, fetching, and closing.
```
<!-- SPDX-SnippetEnd -->

**Good (Alexandrian/Zinsser/Plain Language):**
<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2025 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
# Stores managed objects behind integer handles.
#
# Frontend JavaScript cannot hold Ruby objects. Serializing large
# binary data through JSON on every call is slow and wasteful.
#
# This table stores the object once and hands the frontend a small
# integer "resource ID" (rid) to pass back later.
#
# Use it to share images, file handles, or other heavy objects with
# the WebView.
```
<!-- SPDX-SnippetEnd -->

## 3. Method and Attribute Documentation

### Prose Style

*   **Attributes:** Use concise noun phrases. Avoid "This attribute returns..." or "Getter for...".
    *   *Bad:* "This is the label of the webview."
    *   *Good:* "The unique label identifying this webview."
*   **Methods:** Use active, third-person present tense verbs.
    *   *Bad:* "Will calculate the total."
    *   *Good:* "Calculates the total."
*   **Context:** For complex methods, you may use a condensed version of the Context-Problem-Solution pattern, but keep it brief.

### Syntax Standards

*   **Examples:** All public methods must include at least one usage example. Use `=== Example`.
*   **Attributes:** Use `attr_reader` with documentation comments immediately preceding them.
*   **Parameters:** Use strict RDoc definition lists `[name] description` for parameters in the `initialize` method.
*   **Formatting:** Use `+code+` for simple identifiers (e.g., `+nil+`, `+rid+`) and `<tt>` tags for anything with spaces or punctuation (e.g., `<tt>plugin:image|new</tt>`).
    *   Do **not** use backticks (\`) or markdown-style links `[text](url)`. RDoc does not render them correctly in all contexts.
    *   Do **not** use smart quotes.

### Example

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2025 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
  # The unique label identifying this webview.
  attr_reader :label

  # Creates a new Webview wrapper.
  #
  # [label] String, unique among webviews (e.g., <tt>"main"</tt>).
  # [native] Native::WebView handle from wry.
  def initialize(label:, native:)
    super
  end
```
<!-- SPDX-SnippetEnd -->

## 4. RDoc Specifics

*   **No Endless Methods:** Do **not** use Ruby 3.0+ endless method definitions (`def foo = bar`). RDoc currently has a bug where it fails to correctly parse the end of the method, causing subsequent methods to lose their visibility and comment attachment (they show up as undocumented public methods in `rake rdoc:coverage`). Always use standard `def ... end` blocks.
*   **No YARD:** Do not use `@param`, `@return`, or other YARD tags. Use standard RDoc formats.
*   **Directives:** Use `:nodoc:` for private or internal methods that should not appear in the API docs.
*   **Headings:** Use `===` for section headers like `=== Examples`.
*   **SPDX in Ruby:** Wrap SPDX headers in `#--` / `#++` so they stay out of the rendered docs (per AGENTS.md).
*   **Examples are MIT-0:** Readers copy examples into their own apps, whatever their license. Wrap each example in an SPDX snippet licensed `MIT-0`, hidden from the rendered docs the same way:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# === Example
#
#--
# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++
#   DesktopInputLock.hold(speak: false) { move_the_pointer }
#--
# SPDX-SnippetEnd
#++
```
<!-- SPDX-SnippetEnd -->

## 5. Checklist for Agents

Before finalizing documentation, ask:
1.  Did I explain the *problem* this code solves?
2.  Are my sentences short and active? (Did I remove "allows the user to"?)
3.  Is the code example valid and copy-pasteable?
4.  Did I use `+code+` or `<tt>` for symbols and code values?
5.  Did I document every attribute and parameter?
6.  Did I wrap each example in an SPDX snippet (`MIT-0`), so readers can copy it freely?
