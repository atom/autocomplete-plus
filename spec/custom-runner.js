const { createRunner } = require('atom-jasmine3-test-runner');

const options = {
  specHelper: {
    atom: true,
    attachToDom: true,
    ci: true,
    customMatchers: true,
    jasmineFocused: true,
    jasmineJson: true,
    jasminePass: true,
    jasmineTagged: true,
    mockClock: true,
    mockLocalStorage: true,
    profile: true,
    set: true,
    unspy: true
  },
  silentInstallation: true
};

module.exports = createRunner(options);
