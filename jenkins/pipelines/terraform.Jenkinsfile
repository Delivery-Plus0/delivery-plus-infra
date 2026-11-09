// dev-terraform: plan, then (on approval) apply or destroy the dev stack: the app host with its
// static IP and data volume, its security group and role, and the S3 buckets.
// The platform stack (network, ECR, Jenkins) is applied by an admin, never from here.
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
    timeout(time: 60, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  parameters {
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'plan shows the changes only; apply and destroy ask for approval after the plan.')
    string(name: 'CONFIRM_DESTROY', defaultValue: '', description: 'For destroy only: type delivery-plus-dev. Destroying deletes the data volume, the buckets and the static IP.')
  }
  environment {
    TF_IN_AUTOMATION = '1'
    TF_INPUT = '0'
    STACK = 'terraform/stacks/dev'
  }
  stages {
    stage('Guard') {
      when { expression { params.ACTION == 'destroy' } }
      steps {
        script {
          if (params.CONFIRM_DESTROY != 'delivery-plus-dev') {
            error('Destroy needs CONFIRM_DESTROY=delivery-plus-dev.')
          }
        }
      }
    }
    stage('Lint and test') {
      steps {
        sh 'make tf-lint tf-test'
      }
    }
    stage('Init') {
      steps {
        sh 'scripts/tf-init.sh dev'
      }
    }
    stage('Plan') {
      steps {
        script {
          def destroyFlag = params.ACTION == 'destroy' ? '-destroy' : ''
          def status = sh(returnStatus: true, script: """
            terraform -chdir=\$STACK plan ${destroyFlag} -detailed-exitcode -out=tfplan \
              -var state_bucket=\$STATE_BUCKET -var region=\$AWS_REGION
          """)
          if (status == 1) {
            error('terraform plan failed.')
          }
          env.HAS_CHANGES = status == 2 ? 'true' : 'false'
          sh 'terraform -chdir=$STACK show -no-color tfplan > tfplan.txt'
          archiveArtifacts artifacts: 'tfplan.txt'
          echo(env.HAS_CHANGES == 'true' ? 'The plan has changes (tfplan.txt).' : 'No changes.')
        }
      }
    }
    stage('Approve') {
      when { expression { params.ACTION != 'plan' && env.HAS_CHANGES == 'true' } }
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          script {
            def verb = [apply: 'Apply', destroy: 'Destroy'][params.ACTION]
            input(message: "${verb} the dev stack as planned (see tfplan.txt)?", ok: verb)
          }
        }
      }
    }
    stage('Apply') {
      when { expression { params.ACTION != 'plan' && env.HAS_CHANGES == 'true' } }
      steps {
        sh 'terraform -chdir=$STACK apply -auto-approve tfplan'
      }
    }
    stage('Outputs') {
      when { expression { params.ACTION == 'apply' } }
      steps {
        sh 'terraform -chdir=$STACK output'
      }
    }
  }
  post {
    always {
      sh 'rm -f $STACK/tfplan'
    }
  }
}
