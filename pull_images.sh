#!/bin/bash

# Path to the freeze-values.yaml file
FREEZE_VALUES_FILE="freeze-values.yaml"

# Ensure the freeze-values.yaml file exists
if [[ ! -f "$FREEZE_VALUES_FILE" ]]; then
  echo "Error: File $FREEZE_VALUES_FILE not found!"
  exit 1
fi

# Extract all 'completeImageName' entries from both 'datasourceImages' and 'images'
# The yq command parses the YAML and combines entries from the specified keys
IMAGES=$(yq e '.datasourceImages.*.completeImageName, .images.*.completeImageName' "$FREEZE_VALUES_FILE")

# Check if any images were found
if [[ -z "$IMAGES" ]]; then
  echo "Error: No images found in $FREEZE_VALUES_FILE!"
  exit 1
fi

# Initialize an empty command string to store the combined pull commands
COMMAND=""

# Loop through each image and append it to the command string
for IMAGE in $IMAGES; do
  COMMAND+="crictl pull $IMAGE && "
done

# Remove the trailing " && " to avoid errors in the final command
COMMAND=${COMMAND%&& }

# Display the generated command for logging or debugging purposes
echo "Generated command:"
echo "$COMMAND"

# Execute the generated command
echo "Executing the command..."
eval "$COMMAND"

# Check the exit status of the command execution
if [[ $? -eq 0 ]]; then
  echo "All images pulled successfully."
else
  echo "Failed to pull one or more images."
  exit 1
fi
