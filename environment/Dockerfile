ARG ANSIBLE_RUNNER_VERSION
FROM quay.io/ansible/ansible-runner:$ANSIBLE_RUNNER_VERSION

ENV HOME /tmp

RUN git config --global url."https://github.com/".insteadOf git@github.com:
