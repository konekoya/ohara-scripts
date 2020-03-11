const cp = require("child_process");
const config = require("./config");
require("dotenv").config({ path: config.envPath });

const userName = process.env.USER_NAME;
const masterIp = process.env.K8S_MASTER;
const slaveIp = process.env.K8S_SLAVE;

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const runSsh = options => {
  const { isSlave = false, command = "" } = options;
  const serverIp = isSlave ? slaveIp : masterIp;

  cp.execSync(`ssh ${userName}@${masterIp} ${command}`, {
    stdio: "inherit"
  });
};

module.exports = {
  sleep,
  runSsh
};
