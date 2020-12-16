.PHONY: default
default:
	hugo

future:
	hugo --buildFuture

.PHONY: server
server:
	hugo server --buildDrafts --buildFuture
