// infra-ci: lint and test this repository (every branch). Same checks as the GitHub workflow.
pipeline {
  agent {
    dockerfile {
      filename 'ci/tools.Dockerfile'
      args '--group-add 2375'
    }
  }
  options {
    timestamps()
    ansiColor('xterm')
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  stages {
    stage('Lint') {
      steps {
        sh 'make lint'
      }
    }
    stage('Test') {
      steps {
        sh 'make test'
      }
    }
  }
}
