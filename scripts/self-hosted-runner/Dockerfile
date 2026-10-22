# Ephemeral GitHub Actions runner for MailReserve's Linux CI jobs (`engine`, `ci-gate`).
# Adapted from djask12/certifyrapp scripts/self-hosted-runner.
#
# Linux, not the host macOS: Docker on the Mac runs Linux containers. That is why the engine
# (MailReserveKit) must build on Linux; macOS-only work runs on GitHub-hosted macos-latest.
# Built for the host's native arch (arm64).
#
# Versions are pinned; bump them deliberately and re-run the full pipeline.
FROM swift:6.4.0-noble

ARG RUNNER_VERSION=2.338.0
ARG GH_VERSION=2.102.0
ARG TARGETARCH=arm64

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

# curl/git/ca-certificates/libicu/libssl: the runner's own needs.
# python3-minimal: run_with_timeout.py in the entrypoint.
# jq: scripts/ci/check-coverage.sh. openjdk-21-jre-headless: GreenMail (scripts/ci/start-greenmail.sh).
# libsqlite3-dev: GRDB from Milestone 1. sudo: parity with ubuntu-latest for workflow steps.
# The runner refuses to run as root, so it gets a passwordless-sudo user instead.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq python3-minimal sudo tar unzip zstd \
        libicu74 libssl3 openjdk-21-jre-headless libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash runner \
    && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner

# gh is preinstalled on ubuntu-latest but not here; pinned like the runner.
RUN curl -fsSL -o /tmp/gh.deb \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/gh.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/gh.deb \
    && gh --version

# Fail the build rather than ship an image missing a tool CI relies on.
RUN swift --version && java -version && jq --version

USER runner
WORKDIR /home/runner

RUN curl -fsSL -o runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${TARGETARCH}-${RUNNER_VERSION}.tar.gz" \
    && tar xzf runner.tar.gz \
    && rm runner.tar.gz

COPY --chown=runner:runner entrypoint.sh run_with_timeout.py /home/runner/
ENTRYPOINT ["/home/runner/entrypoint.sh"]
