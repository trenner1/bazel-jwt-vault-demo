# Simple BUILD file for testing bazel-build wrapper

# Test target that requires secrets (simulated)
sh_binary(
    name = "vault_test",
    srcs = ["vault_test.sh"],
)

# Simple echo test that doesn't require secrets
sh_binary(
    name = "simple_test",
    srcs = ["simple_test.sh"],
)