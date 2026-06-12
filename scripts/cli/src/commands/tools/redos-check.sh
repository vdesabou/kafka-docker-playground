regex="${args[--topic-regex]}"
timeout="${args[--timeout]}"

log "🏗 Building jar for redos-check"
docker run -i --rm -v "${root_folder}/scripts/cli/src/redos-check":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -v "${root_folder}/scripts/cli/src/redos-check/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml package > /tmp/result.log 2>&1
if [ $? != 0 ]
then
    logerror "❌ failed to build java component redos-check"
    tail -500 /tmp/result.log
    exit 1
fi
set -e

log "🚀 Executing redos-check with topic regex: $regex and timeout: ${timeout:-1}s"
set +e
docker run -i --rm -v "${root_folder}/scripts/cli/src/redos-check/target:/app" -w /app eclipse-temurin:11 java -jar redos-check-1.0.0-jar-with-dependencies.jar "$regex" "${timeout:-1}" 2>&1
exit_code=$?

if [ $exit_code -eq 0 ]
then
    log "✅ Regex is safe"
    exit 0
elif [ $exit_code -eq 1 ]
then
    log "⚠️  ReDoS vulnerability detected"
    exit 1
elif [ $exit_code -eq 2 ]
then
    log "⏱️  Timeout: topic regex check exceeded ${timeout:-1}s limit"
    exit 2
elif [ $exit_code -eq 3 ]
then
    logerror "❌ error while executing redos-check"
    exit 3
else
    logerror "❌ unexpected error while executing redos-check (exit code: $exit_code)"
    exit 1
fi