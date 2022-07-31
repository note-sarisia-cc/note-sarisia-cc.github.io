.PHONY: default
default:
	hugo

.PHONY: server
server:
	hugo server --buildDrafts --buildFuture
