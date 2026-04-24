# Testing Guide - Zero Manual Steps! 🎯

This guide shows you how to test the Terraform Cloud Connector Tool with **zero manual configuration**.

## 🚀 Quick Test (Recommended)

**One command, complete test:**

```bash
./bootstrap.sh
```

Choose option 1 (Quick Start) and the tool will:
1. ✅ Install dependencies automatically
2. ✅ Configure credentials (prompts once)
3. ✅ Deploy test cluster with Datagen
4. ✅ Validate everything works
5. ✅ Show results

**Expected time**: 2-3 minutes
**Manual steps**: 0 (just enter credentials when prompted)

## 🧪 Test Scenarios

### Scenario 1: First-Time User Test
**Goal**: Verify the complete new-user experience

```bash
# 1. Run bootstrap
./bootstrap.sh

# 2. Choose "Quick Start" (option 1)
# Script runs automatically

# 3. Verify success
make status    # Should show RUNNING connector
make outputs   # Should show cluster details

# 4. Clean up
make destroy
```

**Expected Results**:
- ✅ Cluster ID displayed (lkc-xxxxx)
- ✅ Connector status: RUNNING
- ✅ No errors in output
- ✅ Clean destruction

---

### Scenario 2: Interactive Wizard Test
**Goal**: Test the guided configuration flow

```bash
# 1. Run wizard
./wizard.sh

# 2. Answer prompts:
#    - Connector: Datagen (option 1)
#    - Cloud: AWS (option 1)
#    - Topic: pageviews (default)
#    - Template: PAGEVIEWS (option 1)

# 3. Review and deploy

# 4. Verify
make outputs
```

**Expected Results**:
- ✅ Custom configuration applied
- ✅ Resources match selections
- ✅ User-friendly prompts

---

### Scenario 3: Quick Launch Test
**Goal**: Test one-command scenarios

```bash
# Test Datagen
./quick-launch.sh datagen
make status
make destroy

# Test Pipeline (if you have AWS credentials)
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
./quick-launch.sh pipeline
make status
make destroy
```

**Expected Results**:
- ✅ Immediate deployment
- ✅ Minimal prompts
- ✅ Fast execution

---

### Scenario 4: Multi-Cloud Test
**Goal**: Verify cloud provider flexibility

```bash
# GCP
./quick-launch.sh datagen --cloud GCP --region us-central1
make outputs   # Should show GCP details
make destroy

# Azure
./quick-launch.sh datagen --cloud AZURE --region eastus
make outputs   # Should show Azure details
make destroy
```

**Expected Results**:
- ✅ Cluster in specified cloud
- ✅ Correct region
- ✅ No manual configuration

---

### Scenario 5: Validation Test
**Goal**: Test error handling and validation

```bash
# Run validation
./validate-setup.sh

# Expected checks:
# - Terraform version
# - Confluent credentials
# - Network connectivity
# - Terraform provider
```

**Expected Results**:
- ✅ All checks pass
- ✅ Clear error messages if issues found
- ✅ Suggestions for fixes

---

## 🔄 Continuous Testing Workflow

### Daily Developer Test
```bash
# Morning: Quick sanity check
make setup          # Updates dependencies
make quick-datagen  # Fast test
make destroy        # Clean up
```

### Weekly Integration Test
```bash
# Test all scenarios
./bootstrap.sh      # Full automation test
./wizard.sh         # Interactive test
./quick-launch.sh datagen   # Quick test
./quick-launch.sh pipeline  # Pipeline test (requires AWS)

# Verify all examples
./generate-examples.sh
```

### Release Test
```bash
# 1. Fresh install test
rm -rf .terraform* .env terraform.tfstate*
./bootstrap.sh

# 2. Multi-scenario test
for scenario in datagen; do
    ./quick-launch.sh $scenario
    make status
    make destroy
done

# 3. Documentation test
cat ZERO_CONFIG_INSTALL.md
cat README.md
cat QUICKSTART.md
```

---

## ✅ Test Checklist

Use this checklist for comprehensive testing:

### Installation & Setup
- [ ] `./bootstrap.sh` runs without errors
- [ ] Dependencies auto-install correctly
- [ ] Credentials configuration works
- [ ] `.env` file created
- [ ] Terraform initialized

### Wizard Functionality
- [ ] `./wizard.sh` displays menu
- [ ] Datagen configuration works
- [ ] S3 configuration works (with AWS creds)
- [ ] Cloud selection works
- [ ] Configuration review shows correct values
- [ ] Deployment succeeds

### Quick Launch
- [ ] `./quick-launch.sh datagen` works
- [ ] `./quick-launch.sh pipeline` works (with AWS)
- [ ] Cloud/region flags work
- [ ] Auto-approve flag works

### Resource Creation
- [ ] Cluster created (lkc-xxxxx)
- [ ] Service account created (sa-xxxxx)
- [ ] API keys created
- [ ] Connector deployed (lcc-xxxxx)
- [ ] Connector reaches RUNNING state

### Outputs & Status
- [ ] `make outputs` shows all resources
- [ ] `make status` shows connector status
- [ ] `.ccloud_env` file created
- [ ] Environment variables correct

### Cleanup
- [ ] `make destroy` removes all resources
- [ ] No orphaned resources in Confluent Cloud
- [ ] Local files cleaned up (option)

### Documentation
- [ ] README updated with zero-config info
- [ ] ZERO_CONFIG_INSTALL.md exists and accurate
- [ ] Examples directory populated
- [ ] Scripts have --help flags

### Error Handling
- [ ] Invalid credentials caught early
- [ ] Missing dependencies auto-installed
- [ ] Network errors handled gracefully
- [ ] Clear error messages provided

---

## 🐛 Common Test Issues & Fixes

### Issue: "Terraform not found"
**Fix**: Run `./setup.sh` first

### Issue: "Invalid credentials"
**Fix**: Check API keys are Cloud API Keys (not cluster-specific)

### Issue: "Connector fails to start"
**Fix**: Check connector config in `.terraform/terraform.tfstate`

### Issue: "S3 bucket not found"
**Fix**: Ensure bucket exists and AWS credentials are correct

---

## 📊 Performance Benchmarks

Expected timing for each test:

| Test | Time | Steps |
|------|------|-------|
| `./bootstrap.sh` (Quick Start) | 2-3 min | 0 manual |
| `./wizard.sh` | 3-4 min | 5 questions |
| `./quick-launch.sh datagen` | 2 min | 0 manual |
| `./setup.sh` only | 30 sec | 1 (credentials) |
| `make destroy` | 1-2 min | 0 manual |

---

## 🔍 Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Verbose bootstrap
DEBUG=1 ./bootstrap.sh

# Verbose wizard
DEBUG=1 ./wizard.sh

# Terraform debug
TF_LOG=DEBUG ./quick-launch.sh datagen
```

---

## 🎓 Test Progression

### Level 1: Basic Functionality
- [ ] Bootstrap quick start works
- [ ] Single connector deploys
- [ ] Cleanup works

### Level 2: All Scenarios
- [ ] All quick-launch scenarios work
- [ ] Wizard configurations work
- [ ] Multi-cloud works

### Level 3: Edge Cases
- [ ] Works without prior setup
- [ ] Works with existing .env
- [ ] Handles partial cleanup
- [ ] Re-runs after failure

### Level 4: Integration
- [ ] Works with playground commands
- [ ] Integrates with CI/CD
- [ ] Works in fresh environment

---

## 📋 Automated Test Script

Run all tests automatically:

```bash
#!/bin/bash
# automated-test-suite.sh

echo "🧪 Running Full Test Suite..."

# Test 1: Fresh install
echo "Test 1: Fresh Install"
rm -rf .terraform* .env terraform.tfstate*
./bootstrap.sh --quick
[ $? -eq 0 ] && echo "✅ Pass" || echo "❌ Fail"
make destroy

# Test 2: Wizard
echo "Test 2: Interactive Wizard"
echo -e "1\n1\npageviews\n1\ny" | ./wizard.sh
[ $? -eq 0 ] && echo "✅ Pass" || echo "❌ Fail"
make destroy

# Test 3: Quick Launch
echo "Test 3: Quick Launch"
./quick-launch.sh datagen --auto
[ $? -eq 0 ] && echo "✅ Pass" || echo "❌ Fail"
make destroy

echo "✅ All tests complete!"
```

---

## 🎯 Success Criteria

A successful test run should show:

```
✔ Terraform installed
✔ Dependencies configured
✔ Credentials validated
✔ Cluster created (lkc-xxxxx)
✔ Connector deployed (lcc-xxxxx)
✔ Connector status: RUNNING
✔ Outputs displayed correctly
✔ Resources cleaned up
```

**Zero manual configuration required!** 🚀

---

## 📞 Getting Help

If tests fail:

1. Check `./validate-setup.sh`
2. Review error messages (they're designed to be helpful!)
3. Check documentation: `cat ZERO_CONFIG_INSTALL.md`
4. Enable debug mode: `DEBUG=1 ./bootstrap.sh`
5. Check Terraform state: `terraform show`

**Most common fix**: Just run `./setup.sh` again!
