// ---- implementation-neutral procedures ----------------------------------
//
// Pseudocode belongs between behavior rules and source code. A behavior rule
// says what an observer sees; pseudocode explains a consequential procedure
// without binding the design to one programming language. The constructors
// keep control flow as data, so indentation and keywords are renderer-owned.
#import "schema.typ": *
#import "semantic.typ": *
#import "tokens.typ": *
#import "rules.typ": *

#let pseudo-step(body) = (kind: "step", body: body)
#let pseudo-return(body) = (kind: "return", body: body)
#let pseudo-if(condition, steps, otherwise: none) = (
  kind: "if", condition: condition, steps: steps, otherwise: otherwise,
)
#let pseudo-for(each, over, steps) = (
  kind: "for", each: each, over: over, steps: steps,
)
#let pseudo-repeat(condition, steps) = (
  kind: "repeat", condition: condition, steps: steps,
)

#let _pseudo-check(items, where: "steps") = {
  if type(items) != array {
    panic("pseudocode " + where + "= must be an array of pseudocode steps")
  }
  for (i, item) in items.enumerate() {
    let at = where + "[" + str(i) + "]"
    if type(item) != dictionary {
      panic("pseudocode " + at + " must be built with a pseudo-* constructor")
    }
    let kind = item.at("kind", default: none)
    if kind not in ("step", "return", "if", "for", "repeat") {
      panic("pseudocode " + at + " has unknown step kind " + repr(kind))
    }
    if kind in ("step", "return") and "body" not in item {
      panic("pseudocode " + at + " is missing body")
    }
    if kind in ("if", "repeat") and "condition" not in item {
      panic("pseudocode " + at + " is missing condition")
    }
    if kind == "for" and ("each" not in item or "over" not in item) {
      panic("pseudocode " + at + " requires each and over")
    }
    if kind in ("if", "for", "repeat") {
      _pseudo-check(item.at("steps", default: none), where: at + ".steps")
    }
    if kind == "if" and item.at("otherwise", default: none) != none {
      _pseudo-check(item.otherwise, where: at + ".otherwise")
    }
  }
}

#let _pseudo-row(keyword, body, c, depth: 0, closing: false) = {
  let tone = if closing { FAINT } else { c }
  block(width: 100%, inset: (left: depth * 14pt, y: 2.5pt))[
    #grid(
      columns: (58pt, 1fr),
      column-gutter: 8pt,
      align: (right + top, left + top),
      text(size: 6.4pt, weight: "bold", tracking: 0.45pt, fill: tone)[
        #keyword
      ],
      text(size: 8.2pt, font: "DejaVu Sans Mono", fill: INK)[#body],
    )
  ]
}

#let _pseudo-lines(items, c, depth: 0) = {
  for item in items {
    let kind = item.kind
    if kind == "step" {
      _pseudo-row("DO", item.body, c, depth: depth)
    } else if kind == "return" {
      _pseudo-row("RETURN", item.body, c, depth: depth)
    } else if kind == "if" {
      _pseudo-row("IF", item.condition, c, depth: depth)
      _pseudo-lines(item.steps, c, depth: depth + 1)
      if item.otherwise != none {
        _pseudo-row("OTHERWISE", [], c, depth: depth)
        _pseudo-lines(item.otherwise, c, depth: depth + 1)
      }
      _pseudo-row("END IF", [], c, depth: depth, closing: true)
    } else if kind == "for" {
      _pseudo-row("FOR EACH", [#item.each #h(4pt)IN#h(4pt) #item.over], c, depth: depth)
      _pseudo-lines(item.steps, c, depth: depth + 1)
      _pseudo-row("END FOR", [], c, depth: depth, closing: true)
    } else if kind == "repeat" {
      _pseudo-row("REPEAT", [], c, depth: depth)
      _pseudo-lines(item.steps, c, depth: depth + 1)
      _pseudo-row("UNTIL", item.condition, c, depth: depth, closing: true)
    }
  }
}

#let _pseudo-interface(label, values, c) = {
  if values.len() > 0 {
    grid(
      columns: (58pt, 1fr), column-gutter: 8pt,
      text(size: 6.2pt, weight: "bold", tracking: 0.45pt, fill: c)[#label],
      text(size: 7.6pt, fill: MUTED)[#values.join([#h(5pt)·#h(5pt)])],
    )
  }
}

#let pseudocode(
  id: none,
  title: none,
  inputs: (),
  outputs: (),
  steps: (),
  caption: none,
  accent: "teal",
) = {
  _need("pseudocode", "title", title)
  _enum("pseudocode", "accent", accent, TINTS)
  if id != none and (type(id) != str or id.trim() == "") {
    panic("pseudocode id= must be a non-empty string when supplied")
  }
  if type(inputs) != array or type(outputs) != array {
    panic("pseudocode inputs= and outputs= must be arrays")
  }
  _pseudo-check(steps)
  if steps.len() == 0 {
    _guide("pseudocode.empty", "pseudocode() holds at least one step")
  }
  if context-projection {
    let projected = semantic("pseudocode", fields: (
      id: id, title: title, inputs: inputs, outputs: outputs,
      steps: steps, caption: caption,
    ))
    return if id == none {
      projected
    } else {
      [#_semantic-target("pseudocode-" + id)#projected]
    }
  }

  let c = TINT-COLOR.at(accent)
  let rendered = block(
    width: 100%, breakable: true,
    fill: c.lighten(97%),
    stroke: (top: 1.4pt + c, rest: 0.45pt + c.lighten(58%)),
    radius: 2pt,
    inset: (x: 10pt, y: 8pt),
  )[
    #grid(
      columns: (1fr, auto), align: (left, right),
      text(size: RENDERER-META, weight: "bold", tracking: 0.65pt,
           fill: c)[PSEUDOCODE],
      text(size: RENDERER-COMPACT, weight: "semibold", fill: MUTED)[#title],
    )
    #if inputs.len() > 0 or outputs.len() > 0 [
      #v(6pt)
      #block(width: 100%, inset: (x: 7pt, y: 5pt), fill: SURFACE,
             stroke: 0.4pt + HAIRLINE, radius: 1.5pt)[
        #_pseudo-interface("INPUT", inputs, c)
        #if inputs.len() > 0 and outputs.len() > 0 [#v(2pt)]
        #_pseudo-interface("OUTPUT", outputs, c)
      ]
    ]
    #v(6pt)
    #line(length: 100%, stroke: 0.4pt + c.lighten(58%))
    #v(3pt)
    #_pseudo-lines(steps, c)
    #if caption != none [
      #v(6pt)
      #text(size: 7.5pt, fill: MUTED, style: "italic")[#caption]
    ]
  ]

  if id == none {
    rendered
  } else {
    [#metadata(id)#rendered#label("pseudocode-" + id)]
  }
  v(0.55em)
}
