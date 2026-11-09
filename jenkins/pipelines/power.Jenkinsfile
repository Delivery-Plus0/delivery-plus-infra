// dev-power: stop the dev app host when nobody uses it, start it again later. The static IP, the
// data volume and the buckets stay; Docker brings the stack back up on boot.
pipeline {
  agent {
    dockerfile {
      filename 'ci/tools.Dockerfile'
      args '--group-add 2375'
    }
  }
  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 20, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '50'))
  }
  parameters {
    choice(name: 'ACTION', choices: ['status', 'start', 'stop'], description: 'What to do with the dev app host.')
  }
  stages {
    stage('Power') {
      steps {
        sh '''
          eval "$(scripts/env-info.sh)"
          echo "App host ${INSTANCE_ID}: ${INSTANCE_STATE}"
          case "$ACTION" in
            start)
              aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
              aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
              echo "Started. The stack comes back up on its own; give it two minutes, then:"
              echo "  https://api.${BASE_DOMAIN}/health"
              ;;
            stop)
              aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
              aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
              echo "Stopped. The static IP ${PUBLIC_IP} and the data stay."
              ;;
          esac
        '''
      }
    }
  }
}
