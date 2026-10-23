# Architecture coverage

This map covers architectural responsibilities. Code and executable tests remain
authoritative for implementation detail.

| Responsibility                                                | Status       | Architectural explanation                                                                 |
| ------------------------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------- |
| Documentation guidance and host boundary                      | captured     | [System at a glance](design/design.typ#system-at-a-glance)                                |
| Checked library, schema, and validation scopes                | captured     | [Progressive breakdown](design/design.typ#progressive-breakdown)                          |
| PDF, Markdown, and document gate                              | captured     | [Progressive breakdown](design/design.typ#progressive-breakdown)                          |
| Authoring flow, projection limits, and bundle reproducibility | captured     | [End-to-end walkthrough](design/design.typ#end-to-end-walkthrough)                        |
| Individual widgets and command options                        | standard     | Library contracts, the syntax skill, and executable examples carry this reference detail. |
| Host architecture decisions and implementation correctness    | out-of-scope | The host owns these; this repository documents and validates their representation.        |
