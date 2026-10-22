// SDP Document Template
//
// Layout:
//   Wits          <highest heading>   <title> <- running header, every page
//   --------------------------------------------
//   <page content>
//   --------------------------------------------
//                 <page> / <page total>       <- running footer, every page
//
// Usage:
//   #import "doc_template.typ": doc
//   #show: doc.with(title: "...", course-code: "...", authors: ("...",))

#let wits-blue = rgb("#003b71")
#let wits-gold = rgb("#c99700")

// Finds the current level-1 heading for the running header, mirroring
// LaTeX fancyhdr's \leftmark: whichever level-1 heading most recently
// appeared on or before the current page.
#let current-top-heading() = context {
  let headings = query(heading.where(level: 1))
  let page = here().page()
  let seen = headings.filter(h => h.location().page() <= page)
  if seen.len() > 0 {
    seen.last().body
  } else {
    []
  }
}

#let doc(
  title: "",
  course-code: "",
  institution: "University of the Witwatersrand",
  authors: (),
  date: none,
  ai_declaration: none,
  body,
) = {
  set document(title: title, author: authors)
  set page(
    paper: "a4",
    margin: (top: 3.4cm, bottom: 3.2cm, x: 2.2cm),
    header-ascent: 60%,
    footer-descent: 50%,
    header: context {
      grid(
        columns: (1fr, 1fr, 1fr),
        align: (left, center, right),
        text(size: 9pt)[University of the Witwatersrand],
        text(size: 9pt, style: "italic")[#current-top-heading()],
        text(size: 9pt)[#title],
      )
      v(-6pt)
      line(length: 100%, stroke: 0.5pt + luma(60%))
    },
    footer: context {
      line(length: 100%, stroke: 0.5pt + luma(60%))
      v(-6pt)
      align(center, text(size: 9pt)[
        #counter(page).display("1") / #context counter(page).final().first()
      ])
    },
  )


  set text(size: 11pt)
  show raw: set text(font: "Berkeley Mono")
  show link: set text(fill: blue)
  set heading(numbering: "1.1")

  show heading.where(level: 1): it => {
    v(1.2em)
    text(size: 18pt, weight: "semibold")[#it]
    v(0.6em)
  }
  show heading.where(level: 2): it => {
    v(1em)
    text(size: 14pt, weight: "semibold")[#it]
    v(0.4em)
  }

  align(center)[
    #v(0.3cm)
    #text(size: 22pt, weight: "bold", stretch: 150%)[#title]
    #v(0.1cm)
    #if authors.len() > 0 {
      text(size: 12pt)[#authors.join(", ")]
      linebreak()
    }
    #if date != none { text(size: 10pt, fill: luma(40%))[#date] }
    #v(0.8cm)
  ]

  body

  line(length: 100%, stroke: gray)

  if ai_declaration != none {
    text[*AI Declaration*: #ai_declaration]
  } else {
    text[*AI Declaration*: The preceding document was written without the assistance of AI]
  }
}
