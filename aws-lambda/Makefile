BUILD_DIR=../build/aws-lambda

build:
	npx webpack --config webpack.config.js
	rm -f $(BUILD_DIR)/recoverto-claim.zip
	# build recoverto-claim
	rm -rf $(BUILD_DIR)/recoverto-claim.d
	mkdir $(BUILD_DIR)/recoverto-claim.d
	cp recoverto-claim.js $(BUILD_DIR)/recoverto-claim.d/index.js
	cp $(BUILD_DIR)/recoverto-aws-lambda-bundle.js* $(BUILD_DIR)/recoverto-claim.d/
	cd $(BUILD_DIR)/recoverto-claim.d && zip -r ../recoverto-claim.zip .

.PHONY: build
