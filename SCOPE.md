You are an expert Principal Software Architect and UX Engineer specializing in input method editors (IMEs), text manipulation engines, and developer/creator productivity tools.

Your task is to design and implement a complete, production-ready specification and codebase for an **Abbreviation Expander Application** designed specifically for **Copywriters** and **QA Engineers**.

---

### Context & Goal

Users frequently type repetitive text (e.g., marketing disclaimers, brand tone guidelines, bug report templates, environment specs). As the user types, the application actively monitors keystrokes. When typed characters match a defined abbreviation prefix, a subtle popup appears at the cursor showing matching expansions. The user can filter results by continuing to type, navigate via arrow keys, and press `Tab` to expand. Any whitespace character (Space, Enter, Tab on empty popup, etc.) or dismissal key cancels the watch state instantly.

---

### Key Requirements

#### 1. Core Behavior & State Machine

* **Monitoring State (`IDLE` vs `WATCHING`)**:
* Buffer keystrokes as the user types printable characters.
* Immediately check the buffer against a pre-loaded dictionary of abbreviations.


* **Popup Display (`POPUP_ACTIVE`)**:
* Open a floating UI popup positioned precisely relative to the text cursor position.
* Highlight the top matching expansion by default.


* **Dynamic Narrowing**:
* As extra characters are typed, dynamically filter the candidate expansions.
* If additional typing results in **zero matches**, automatically close the popup and reset/cancel the watch state.


* **Expansion via Tab**:
* If the popup is open, pressing `Tab` intercepts the default tab key, replaces the typed abbreviation in the text control with the selected expansion, and dismisses the popup.


* **Cancellation Logic**:
* Whitespace characters (`Space`, `Enter`, `Tab` when no popup is active), non-printable shortcut triggers, or `Escape` MUST immediately cancel the watch state, clear the key buffer, and hide the popup.



#### 2. Target Audience Specific Features

* **Copywriters**: Support multi-line expansions, dynamic dynamic date/variable substitution (e.g., `{{date}}`, `{{clipboard}}`), and clean formatted text handling.
* **QA Engineers**: Support structured markdown templates (e.g., Steps to Reproduce, Expected vs Actual Results, Environment Specs) and rapid, zero-latency keystroke processing.

---

### Step-by-Step Instructions for Output Generation

1. **Thinking & Outlining (Mandatory)**:
* Before writing the code/specification, write a `<thought_process>` section where you outline the core state machine transitions, edge cases (e.g., backspace, pasting text, rapid typing), and DOM/OS API cursor tracking techniques.


2. **System Architecture & State Machine**:
* Provide a visual or structured state transition table covering `IDLE`, `BUFFERING`, `POPUP_ACTIVE`, and `EXPANDED/CANCELLED`.


3. **Complete Implementation Code**:
* Deliver production-ready code in TypeScript/JavaScript (Web/Browser Extension context or Native API wrapper).
* Use an efficient data structure (e.g., a **Trie** or prefix tree) to ensure sub-millisecond lookup and filtering performance.
* Ensure explicit event management (`keydown`, `input`, cursor positioning calculation).


4. **Sample Abbreviation Dictionary**:
* Provide a comprehensive JSON dictionary featuring realistic presets tailored specifically for Copywriters and QA Engineers.


5. **Edge Case & Validation Matrix**:
* Detail how the engine handles edge cases: Backspacing through an abbreviation, pasting text, focus loss, rapid typing without lag, and caret positioning near screen boundaries.



---

### Mini-Examples of Quality Standards

#### ❌ BAD Output (Vague, incomplete, missing state handling):

> "You can use an event listener on keydown. If typed key matches 'bug', show a div with 'Bug Report Template'. When tab is pressed, set element value to the template."

#### ✅ GOOD Output (Precise, state-driven, complete event control):

> ```typescript
> // Handles state transitions cleanly and guards default key behaviors
> function handleKeyDown(event: KeyboardEvent): void {
>   if (state === EngineState.POPUP_ACTIVE && event.key === 'Tab') {
>     event.preventDefault(); // Prevent focus shift
>     expandSelectedAbbreviation(currentlySelectedMatch);
>     resetWatchState();
>     return;
>   }
>   if (/\s/.test(event.key)) {
>     resetWatchState(); // Whitespace cancels watch
>     return;
>   }
>   // Continue buffering and prefix lookup...
> }
> 
> ```
> 
> 

---

### Constraints & Quality Rules

* **No Placeholders**: Do NOT leave `// TODO: implement logic here` or truncated code blocks. Provide fully written functions.
* **Performance**: Lookups and popup filtering must execute in $O(k)$ time where $k$ is the length of the abbreviation string.
* **Tone**: Technical, structured, authoritative, and direct.