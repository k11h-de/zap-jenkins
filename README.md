# zap-jenkins
Jenkins Pipeline for security scanning with owasp zap periodically inside Docker

**features:**
* supports concurrent runs
* supports scanning using authentication (stored inside context files)
* support for exclude regex
* publishes scan results in json, xml and html
* support for cron triggers 
* portable because inside Docker

# requirements

* `docker` and `jq` installed on jenkins node
* in order to run scans periodically via a cron expression, you need [parameterized-scheduler](https://plugins.jenkins.io/parameterized-scheduler/) jenkins plugin
* to allow rendering of results file, you need [htmlpublisher jenkins plugin](https://plugins.jenkins.io/htmlpublisher/)


# adding a new target

to add a new target you need to
- add it to [Jenkinsfile](Jenkinsfile) variable `targets`
- optional: add a context file to folder [zap-context](zap-context) see [docs](https://github.com/Grunny/zap-cli#running-scans-as-authenticated-users)
- optional: if you want to run periodically; add a line to [Jenkinsfile](Jenkinsfile) -> pipeline -> triggers -> parameterizedCron

# excluding paths from scanning

due to a [know bug](https://github.com/Grunny/zap-cli/issues/79), the zap-cli does not respect the `<excregexes>` section of zap context files 
so there is a slightly modified implementation to work around this.

You simply need to place a file called `<target>.context.exclude` in [contexts](contexts) with one exclude regex per line
Please refer to the examples.