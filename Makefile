all: cards
	zig build-exe -lc ./src/main.zig -fno-stack-protector -fno-omit-frame-pointer
	zig build-lib -lc -dynamic ./src/engine_base.zig -fno-stack-protector -fno-omit-frame-pointer

nice: cards
	rm -rf ./src_preprocessed/
	./preprocess.py
	zig build-exe -lc ./src_preprocessed/main.zig  -O ReleaseFast -fno-strip -fno-stack-protector -fno-omit-frame-pointer
	zig build-lib -lc -dynamic ./src_preprocessed/engine_base.zig -fno-stack-protector -fno-omit-frame-pointer -O ReleaseFast -fno-strip 

final: nice
	./strip.py main
	./strip.py libengine_base.so

final-symbols: nice
	strip -g main

cards:
	zig build-exe ./src/basic_decks.zig -fno-stack-protector -fno-omit-frame-pointer
	rm data/cards/* || true
	rm poller/cards/* || true
	rm exploits/cards/* || true
	./basic_decks > /dev/null 2>/dev/null
	mkdir poller/cards/ -p
	mkdir exploits/cards/ -p
	cp data/cards/op_* poller/cards/
	cp data/cards/op_* exploits/cards/
	rm data/cards/op_* || true

crypto_client: src/crypto_client.zig
	zig build-exe ./src/crypto_client.zig -fno-stack-protector -fno-omit-frame-pointer

CHAL_NAME?=nautro
PORT?=8080

docker:
	docker build -t $(CHAL_NAME):builder --target builder .
	docker build -t $(CHAL_NAME):latest .

run:
	echo "Running $(CHAL_NAME) on port $(PORT)"
	docker rm -f $(CHAL_NAME)-test || true
	sh -c "echo 'flug{this-is-an-example-flag-please-run-your-exploit-against-the-real-server}' > example_flag.txt"
	chmod 777 example_flag.txt
	echo "Server last restarted at $(date)" > last_update.txt
	docker run \
		--name $(CHAL_NAME)-test --rm \
		-p $(PORT):$(PORT) \
		-v $(shell pwd)/example_flag.txt:/flag \
		-v $(shell pwd)/last_update.txt:/app/static/last_update.txt \
		-i $(CHAL_NAME):latest
