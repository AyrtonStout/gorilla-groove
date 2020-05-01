const version = '3.3.2';
const commitHash = require('child_process')
	.execSync('git rev-parse --short HEAD')
	.toString();

const result = version + '-' + commitHash
console.log(result);

return result
