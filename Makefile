NAME = maxswjeon/openldap
VERSION = 2.6.3

.PHONY: build build-nocache run sh push push-latest release git-tag-version

all: build

build:
	docker build -t $(NAME):$(VERSION) --rm .

build-nocache:
	docker build -t $(NAME):$(VERSION) --no-cache --rm .

tag:
	docker tag $(NAME):$(VERSION) $(NAME):latest

push:
	docker push $(NAME):$(VERSION)

push-latest:
	docker push $(NAME):latest

release: build tag push push-latest

git-tag-version:
	git tag -a v$(VERSION) -m "Release v$(VERSION)"
	git push origin $(VERSION)

run:
	docker run -p 389:389 -p 636:636 --rm -v certificates:/certificates -v $(shell pwd)/dhparam:/dhparam -it --env-file .env $(NAME):$(VERSION)

sh:
	docker run --rm -v certificates:/certificates -v $(shell pwd)/dhparam:/dhparam -it --env-file .env --entrypoint sh $(NAME):$(VERSION)
