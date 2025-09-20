load("@broker_pip_deps//:requirements.bzl", "requirement")
load("@rules_python//python:defs.bzl", "py_binary", "py_library")

py_library(
    name = "broker_lib",
    srcs = ["app.py"],
    deps = [
        requirement("fastapi"),
        requirement("uvicorn"),
        requirement("httpx"),
        requirement("python-dotenv"),
        requirement("joserfc"),
        requirement("cryptography"),
    ],
    data = [
        "jwks.json",
        "signer_keys.json",
    ],
    visibility = ["//visibility:public"],
)

py_binary(
    name = "broker",
    srcs = ["start.py"],
    deps = [
        ":broker_lib",
        requirement("uvicorn"),
    ],
    data = [
        "jwks.json",
        "signer_keys.json",
    ],
    main = "start.py",
    visibility = ["//visibility:public"],
)

py_binary(
    name = "gen_keys",
    srcs = ["gen_keys.py"],
    deps = [
        requirement("joserfc"),
        requirement("cryptography"),
    ],
    main = "gen_keys.py",
    visibility = ["//visibility:public"],
)