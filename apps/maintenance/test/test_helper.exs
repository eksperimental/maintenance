# The token is read when it is used, so tests that build authenticated URLs need one.
System.put_env("GITHUB_ACCESS_TOKEN", "test-token")

ExUnit.start()
