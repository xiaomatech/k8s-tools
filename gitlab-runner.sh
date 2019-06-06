sudo wget -O /usr/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64

sudo chmod +x /usr/bin/gitlab-runner

sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash

gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.example.com/" \
  --registration-token "fweafwaefweafwaefweafwae" \
  --executor "shell" \
  --description "gitlab-runner" \
  --run-untagged="true" \
  --locked="false" \
  --access-level="not_protected"
  
  gitlab-runner install --user=gitlab-runner --working-directory=/data/gitlab-runner
  
  gitlab-runner start
