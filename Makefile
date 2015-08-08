S := $(CURDIR)
O := $(S)

REPOMAN_TRAVIS_SRC_URI = \
	https://raw.githubusercontent.com/mrueg/repoman-travis/master/.travis.yml

TRAVIS_APPEND_FILE = $(S)/.travis.yml.append

PHONY =

PHONY += default
default: travis

PHONY += clean
clean:
	rm -f -- $(O)/.travis.yml.new

travis: $(O)/.travis.yml
	git diff --quiet -- '$(<)' || case $${?} in \
		1) git commit '$(<)' -m 'update $(<F)' ;; \
		*) exit 5 ;; \
	esac

$(O)/.travis.yml: FORCE
	mkdir -p -- '$(@D)'
	rm -f -- '$(@).new'

	wget '$(REPOMAN_TRAVIS_SRC_URI)' -O '$(@).new'

	{ \
		true $(foreach f,$(TRAVIS_APPEND_FILE),\
			&& { test ! -f '$(f)' || cat '$(f)'; }); \
	} >> '$(@).new'

	mv -f -- '$(@).new' '$(@)'


FORCE:

.PHONY: $(PHONY)
