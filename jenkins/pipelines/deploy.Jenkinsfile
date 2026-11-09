// dev-deploy: one backend commit and the three web apps to the dev environment.
//
//   1. check out the backend at BACKEND_REF (the image tag is its commit);
//   2. run the backend's lint, tests and build (npm run verify);
//   3. build the 12 service images and push them to ECR (skipped for tags already there);
//   4. build the web apps against this environment's API;
//   5. deploy with Ansible: config, pull, Kafka topics, start, wait until healthy, first admin;
//   6. smoke-test from the outside; optionally load demo data.
pipeline {
  agent any
  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    timeout(time: 90, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  parameters {
    string(name: 'BACKEND_REF', defaultValue: 'dev', description: 'Backend branch, tag or commit (Delivery-Plus0/delivery-plus).')
    string(name: 'APPS_REF', defaultValue: 'dev', description: 'Branch of the three app repositories for the web builds.')
    booleanParam(name: 'RUN_BACKEND_TESTS', defaultValue: true, description: 'npm run verify (lint, unit tests, build) before building images.')
    booleanParam(name: 'BUILD_WEB_APPS', defaultValue: true, description: 'Build and deploy the customer, driver and restaurant web apps.')
    booleanParam(name: 'SEED_DEMO', defaultValue: false, description: 'Load the backend demo data (npm run seed:demo) after the deploy.')
  }
  environment {
    ANSIBLE_FORCE_COLOR = '1'
    ANSIBLE_PRIVATE_NETWORK = 'true'
    ANSIBLE_CONFIG = "${WORKSPACE}/ansible/ansible.cfg"
    // Containers run as the jenkins uid with no home of their own: npm, Expo and Ansible write here.
    HOME = "${WORKSPACE}/.home"
    NPM_CONFIG_CACHE = "${WORKSPACE}/.npm"
  }
  stages {
    stage('Backend source') {
      steps {
        sh 'mkdir -p "$HOME" "$NPM_CONFIG_CACHE"'
        dir('src/backend') {
          checkout scmGit(branches: [[name: params.BACKEND_REF]], userRemoteConfigs: [[url: env.BACKEND_REPO]])
          script {
            env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short=12 HEAD').trim()
            currentBuild.description = "backend ${params.BACKEND_REF} @ ${env.IMAGE_TAG}"
          }
        }
      }
    }
    stage('Environment') {
      agent {
        dockerfile {
          filename 'ci/tools.Dockerfile'
          args '--group-add 2375'
          reuseNode true
        }
      }
      steps {
        script {
          def info = sh(returnStdout: true, script: 'scripts/env-info.sh').trim()
          info.split('\n').each { line ->
            def (key, value) = line.split('=', 2)
            env[key] = value
          }
          if (env.INSTANCE_STATE != 'running') {
            error("The app host is ${env.INSTANCE_STATE}. Start it with dev-power first.")
          }
          echo "Deploying ${env.IMAGE_TAG} to ${env.BASE_DOMAIN} (${env.PUBLIC_IP})"
        }
      }
    }
    stage('Backend tests') {
      when { expression { params.RUN_BACKEND_TESTS } }
      agent {
        docker {
          image 'node:22-bookworm'
          reuseNode true
        }
      }
      steps {
        dir('src/backend') {
          sh 'npm ci --no-audit --no-fund && npm run verify'
        }
      }
    }
    stage('Images') {
      agent {
        dockerfile {
          filename 'ci/tools.Dockerfile'
          args '--group-add 2375 -v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        sh 'scripts/build-images.sh src/backend'
      }
    }
    stage('Web apps') {
      when { expression { params.BUILD_WEB_APPS } }
      agent {
        docker {
          image 'node:22-bookworm'
          reuseNode true
        }
      }
      steps {
        sh 'rm -rf web && mkdir -p web/routes'
        script {
          def apps = [customer: env.CUSTOMER_APP_REPO, driver: env.DRIVER_APP_REPO, restaurant: env.RESTAURANT_APP_REPO]
          apps.each { name, repo ->
            dir("src/${name}") {
              checkout scmGit(branches: [[name: params.APPS_REF]], userRemoteConfigs: [[url: repo]])
              // One at a time: each export needs ~2 GB of memory.
              sh """
                npm ci --no-audit --no-fund
                EXPO_PUBLIC_API_BASE_URL=https://api.\$BASE_DOMAIN CI=1 \
                  npx expo export --platform web --output-dir \$WORKSPACE/web/${name} --clear
              """
            }
            sh "python3 scripts/caddy-routes.py web/${name} > web/routes/${name}.caddy"
          }
        }
      }
    }
    stage('Deploy') {
      agent {
        dockerfile {
          filename 'ci/tools.Dockerfile'
          args '--group-add 2375'
          reuseNode true
        }
      }
      steps {
        withCredentials([
          sshUserPrivateKey(credentialsId: 'app-ssh', keyFileVariable: 'SSH_KEY'),
          usernamePassword(credentialsId: 'dev-admin', usernameVariable: 'DEV_ADMIN_EMAIL', passwordVariable: 'DEV_ADMIN_PASSWORD'),
        ]) {
          dir('ansible') {
            sh """
              ansible-playbook playbooks/deploy.yml --private-key "\$SSH_KEY" \
                -e deploy_backend_dir=\$WORKSPACE/src/backend \
                -e deploy_backend_ref=${params.BACKEND_REF} \
                -e deploy_image_tag=\$IMAGE_TAG \
                ${params.BUILD_WEB_APPS ? '-e deploy_web_dir=$WORKSPACE/web' : ''}
            """
          }
        }
      }
    }
    stage('Smoke test') {
      agent {
        dockerfile {
          filename 'ci/tools.Dockerfile'
          args '--group-add 2375'
          reuseNode true
        }
      }
      steps {
        sh "scripts/smoke-test.sh ${params.BUILD_WEB_APPS ? '' : '--skip-web'}"
      }
    }
    stage('Demo data') {
      when { expression { params.SEED_DEMO } }
      agent {
        docker {
          image 'node:22-bookworm'
          reuseNode true
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dev-admin', usernameVariable: 'TEST_ADMIN_EMAIL', passwordVariable: 'TEST_ADMIN_PASSWORD')]) {
          dir('src/backend') {
            sh '''
              [ -d node_modules ] || npm ci --no-audit --no-fund
              API_URL=https://api.$BASE_DOMAIN npm run seed:demo
            '''
          }
        }
      }
    }
  }
  post {
    success {
      echo """
        Deployed backend ${env.IMAGE_TAG} to the dev environment:
          API         https://api.${env.BASE_DOMAIN}  (static IP ${env.PUBLIC_IP})
          Customer    https://app.${env.BASE_DOMAIN}
          Driver      https://driver.${env.BASE_DOMAIN}
          Restaurant  https://restaurant.${env.BASE_DOMAIN}
      """.stripIndent()
    }
  }
}
