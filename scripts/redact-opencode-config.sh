#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /explicit/path/to/opencode.json\n' "$0" >&2
  exit 64
fi

INPUT=$1

if [[ ! -f "$INPUT" ]]; then
  printf 'Error: input is not a regular file\n' >&2
  exit 66
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: jq is required\n' >&2
  exit 69
fi

if ! jq empty "$INPUT" >/dev/null 2>&1; then
  printf 'Error: input is not valid JSON\n' >&2
  exit 65
fi

jq '
  def normalized_key:
    ascii_downcase | gsub("[-_]"; "");
  def sensitive_key:
    normalized_key |
    test("^(header|headers|authorization|bearer|env|environment|url|urls|uri|uris|endpoint|endpoints|dsn|dsns|connectionstring|connectionstrings|.*(token|tokens|secret|secrets|password|passwords|passwd|credential|credentials|apikey|apikeys|accesskey|accesskeys|accesskeyid|privatekey|privatekeys))$");
  def sensitive_command_argument:
    type == "string" and
    test("(^|[-_/])(authorization|auth[-_]?token|token|secret|password|api[-_]?key|credential)(=|:|$)"; "i");
  def redact_command:
    if [.. | strings | select(sensitive_command_argument)] | length > 0 then
      "<redacted>"
    else
      .
    end;
  def redact:
    if type == "object" then
      with_entries(
        if (.key | sensitive_key) then
          .value = "<redacted>"
        elif (.key | ascii_downcase) == "command" then
          .value |= redact_command
        else
          .value |= redact
        end
      )
    elif type == "array" then
      map(redact)
    else
      .
    end;
  redact
' "$INPUT"
