# SKILL.md - pdf-reader

## Overview
Pdf reader skeleton for packaging flow in ai-feature-pack. Basic CLI and Python utility stubs provided for quick integration.

## Usage
- pdf-reader <path>
- pdf-reader <path> -p <pages> -f <md|json|txt>

## Flow
1) Validate input path
2) Produce either Markdown/JSON/TXT output stub
3) Hook into packaging flow

## Dependencies
- Python 3.x
- bash

## Notes
- This is a skeleton; implement real extraction later using PyMuPDF or pdfminer.s
