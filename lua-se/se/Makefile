LIB_DEPENDS	:= se
LIB_CLEAN	:= $(LIB_DEPENDS:%=clean-%)
LIB_BIN		:= $(LIB_DEPENDS:%=bin/%.so)

TEST_SRC	:= $(wildcard test/test_*.lua)
TEST_TARGET	:= $(TEST_SRC:test/%.lua=%)

.PHONY: all clean test $(TEST_TARGET)

all:
	for lib in $(LIB_DEPENDS); do \
		$(MAKE) -C $$lib && cp $$lib/$$lib.so bin/$$lib.so || exit 1; \
	done
	#cp se/selua bin/selua

clean: $(LIB_CLEAN)
	rm -f $(LIB_BIN) bin/selua

$(LIB_CLEAN):
	$(MAKE) clean -C $(@:clean-%=%)

test: $(TEST_SRC)
	@for src in $(TEST_SRC); do \
		echo ++++++ selua $$src ++++++; \
	   	LUA_PATH='bin/?.lua' LUA_CPATH='bin/?.so' selua $$src; \
	done

$(TEST_TARGET):%:test/%.lua all
	@echo ++++++ selua $< ++++++
	@LUA_PATH='bin/?.lua' LUA_CPATH='bin/?.so' MALLOC_TRIM_THRESHOLD_=1048576 bin/selua $<
