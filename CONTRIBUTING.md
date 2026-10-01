# Contributing

Boat Deck is a small, independently maintained macOS client. Keep changes focused
on making it easy to build and useful to people managing their own Boat account.
There is no release, App Store, or notarization workflow to maintain.

1. Install Command Line Tools 26+ or select Xcode 26+. See the README for build requirements.
2. Run `make test` and `make build`. Neither command installs or launches the app.
3. For UI changes, check the affected screen at narrow and wide window sizes.
4. Open a pull request explaining what changed and how you checked it.

Regression checks compile with plain Swift and use synthetic data, temporary
files, mocked HTTP responses, and local child processes. No Boat credentials or
paid sandboxes are needed. Add tests for behavior that could lose data, expose
credentials, or repeat commands; ordinary visual adjustments do not need a test.

Do not attach API keys, account exports, command histories, private file contents,
or old response-body logs to issues or pull requests. Use a GitHub noreply email
if you want to keep your email private in commits. Screenshots should use sample
account names and sandbox data.

Contributions are under the repository's MIT license.
