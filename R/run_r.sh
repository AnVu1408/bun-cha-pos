#!/bin/bash
# R Runner with proper environment setup

# Set R framework path
export R_HOME="/Users/anvu/R-framework/R.framework/Versions/4.4-arm64/Resources"

# Create the necessary directories and files for R to run
mkdir -p ~/Library/R.framework/Resources/etc

# Create ldpaths file
cat > ~/Library/R.framework/Resources/etc/ldpaths << 'LDPATHS_EOF'
R_HOME_DIR=/Users/anvu/R-framework/R.framework/Versions/4.4-arm64/Resources
R_INCLUDE_DIR=/Users/anvu/R-framework/R.framework/Versions/4.4-arm64/Resources/include
R_DOC_DIR=/Users/anvu/R-framework/R.framework/Versions/4.4-arm64/Resources/doc
R_LIBS_USER=${R_LIBS_USER-'~/Library/R/4.4-arm64/library'}
R_LIBS_SITE=${R_LIBS_SITE-'/Users/anvu/R-framework/R.framework/Versions/4.4-arm64/Resources/library'}
R_LIBS=${R_LIBS-${R_LIBS_SITE}}
LDPATHS_EOF

# Run R with proper environment
exec /Users/anvu/R-framework/R.framework/Versions/4.4-arm64/Resources/bin/R "$@"
