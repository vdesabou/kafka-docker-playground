# How to Test - Simple Steps 🧪

## ⚡ Ultra Quick Test (1 Minute)

```bash
cd ccloud/terraform-cloud-connector
./bootstrap.sh
```

**Choose option 1** when prompted. That's it!

The script will:
- ✅ Install everything you need
- ✅ Ask for your Confluent Cloud credentials once
- ✅ Deploy a test cluster with Datagen
- ✅ Show you the results

**Clean up when done:**
```bash
make destroy
```

---

## 🎯 Testing Different Scenarios

### Test 1: Complete Automation (Recommended)
```bash
./bootstrap.sh → Choose "Quick Start"
make status    → Verify connector is RUNNING
make destroy   → Clean up
```
**Time**: 2-3 minutes

---

### Test 2: Interactive Wizard
```bash
./wizard.sh
# Answer 4 questions (takes 30 seconds)
# Script deploys automatically
make destroy
```
**Time**: 3-4 minutes

---

### Test 3: One-Command Launch
```bash
./quick-launch.sh datagen
make status
make destroy
```
**Time**: 2 minutes

---

### Test 4: Multi-Cloud
```bash
# Test on GCP
./quick-launch.sh datagen --cloud GCP --region us-central1
make destroy

# Test on Azure
./quick-launch.sh datagen --cloud AZURE --region eastus
make destroy
```

---

## ✅ What Success Looks Like

After running any test, you should see:

```
✔ Terraform installed
✔ Dependencies configured
✔ Credentials validated
✔ Cluster created (lkc-xxxxx)
✔ Connector deployed (lcc-xxxxx)
✔ Connector status: RUNNING
```

Then check:
```bash
make outputs   # Shows cluster details
make status    # Shows connector status
```

---

## 🚀 Make Shortcuts

```bash
make bootstrap      # Complete automation
make wizard         # Interactive setup
make quick-datagen  # Fast Datagen test
make quick-pipeline # Full pipeline test
make setup          # Setup dependencies only
```

---

## 📋 Quick Test Checklist

- [ ] Run `./bootstrap.sh`
- [ ] Enter credentials when prompted
- [ ] Verify cluster created (lkc-xxxxx shown)
- [ ] Verify connector running (`make status`)
- [ ] View outputs (`make outputs`)
- [ ] Clean up (`make destroy`)

---

## 🐛 If Something Goes Wrong

```bash
# Re-run setup
./setup.sh

# Validate environment
./validate-setup.sh

# Check what's deployed
make outputs
terraform show

# Force cleanup
make destroy
terraform destroy -auto-approve
```

---

## 💡 Testing Tips

1. **First time?** Use `./bootstrap.sh` → Quick Start
2. **Want to experiment?** Use `./wizard.sh`
3. **Need speed?** Use `./quick-launch.sh`
4. **Need AWS?** Set credentials first:
   ```bash
   export AWS_ACCESS_KEY_ID="your-key"
   export AWS_SECRET_ACCESS_KEY="your-secret"
   ./quick-launch.sh pipeline
   ```

---

## 📊 Expected Timing

| Command | Duration | Manual Steps |
|---------|----------|--------------|
| `./bootstrap.sh` | 2-3 min | 0 |
| `./wizard.sh` | 3-4 min | 4 questions |
| `./quick-launch.sh` | 2 min | 0 |
| `make destroy` | 1-2 min | 0 |

---

## 🎉 That's It!

**No manual configuration. No reading docs. Just working clusters.**

For detailed testing scenarios, see `TESTING.md`
