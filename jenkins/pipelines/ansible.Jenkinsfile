// dev-ansible: configure the app host (OS, Docker, data volume, the stack's environment and Caddy).
// Check mode by default: it shows what would change. Deploys go through dev-deploy.
// The Jenkins host isn't configured from here (it would restart itself mid-run): an admin runs
// playbooks/jenkins.yml (docs/bootstrap.md).
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
    disableConcurrentBuilds()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  parameters {
    booleanParam(name: 'CHECK_MODE', defaultValue: true, description: 'Dry run (--check --diff): show the changes without making them.')
  }
  environment {
    ANSIBLE_FORCE_COLOR = '1'
    ANSIBLE_PRIVATE_NETWORK = 'true'
    ANSIBLE_CONFIG = "${WORKSPACE}/ansible/ansible.cfg"
  }
  stages {
    stage('Lint') {
      steps {
        sh 'make ansible-lint'
      }
    }
    stage('Inventory') {
      steps {
        dir('ansible') {
          sh 'ansible-inventory --graph'
        }
      }
    }
    stage('Configure the app host') {
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'app-ssh', keyFileVariable: 'SSH_KEY')]) {
          dir('ansible') {
            sh """
              ansible-playbook playbooks/app.yml --private-key "\$SSH_KEY" ${params.CHECK_MODE ? '--check --diff' : ''}
            """
          }
        }
      }
    }
  }
}
