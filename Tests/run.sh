#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -o "$test_dir/ReadingChecks" Sources/Suibiancha/Models.swift Sources/Suibiancha/ExpressionLinks.swift Sources/Suibiancha/SentencePatterns.swift Sources/Suibiancha/TextFlow.swift Sources/Suibiancha/Services.swift Sources/Suibiancha/ArticlePractice.swift Sources/Suibiancha/ArticleLibrary.swift Sources/Suibiancha/ArticleImport.swift Tests/ArticleImportChecks.swift Tests/ExpressionChecks.swift Tests/SentencePatternChecks.swift Tests/ReadingChecks.swift
"$test_dir/ReadingChecks" "$@"

swiftc -o "$test_dir/ArticlePracticeChecks" Sources/Suibiancha/ArticlePractice.swift Tests/ArticlePracticeChecks.swift
"$test_dir/ArticlePracticeChecks"

swiftc -o "$test_dir/WindowPresentationChecks" Sources/Suibiancha/WindowPresentationIntent.swift Tests/WindowPresentationChecks.swift
"$test_dir/WindowPresentationChecks"
