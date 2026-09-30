#!/usr/bin/env bats
load helpers

setup() { common_setup; }

@test "help prints usage and exits 0" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-watch"* ]]
  [[ "$output" == *"snapshot"* ]]
}

@test "unknown subcommand exits 1 with a message" {
  run "$BIN" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}
