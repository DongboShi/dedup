SHELL:=/bin/bash
DS:=train
# data/pubs_$(DS).json
-include $(DS)_names.mk
ifndef $(DS)_names
$(DS)_names:=$(shell jq -r 'keys[]' < data/pubs_$(DS).json)
$(DS)_names.mk:
	echo '$(DS)_names:=$($(DS)_names)' > $@
endif

assignment_validate.zip: assignment_validate.json
	ln -sf $^ result.json
	zip -9 $@ result.json
data/stage_$(DS).json: data/pubs_$(DS).json
	./baseline.py $^ -o $@

data/venue_bag_$(DS).json: data/pubs_$(DS).json
	./venue_bag.py $^ -o $@
data/org_bag_${DS}.json: data/${DS}/author
	./org_bag.py $^ -o $@

org_bag.zip: org_bag.json
	ln -sf $^ result.json
	zip -9 $@ result.json

features/$(DS)/csv_flag: data/pubs_$(DS).json
	mkdir -p $(dir $@)/{item0,author0,abstract,keywords}
	./data_transfer.R $^ -o $(dir $@)
	touch $@

features/$(DS)/author0/%.csv: | features/$(DS)/csv_flag
features/$(DS)/item0/%.csv: | features/$(DS)/csv_flag
features/$(DS)/abstract/%.csv: | features/$(DS)/csv_flag
features/$(DS)/keywords/%.csv: | features/$(DS)/csv_flag

features/$(DS)/author/%.csv: features/$(DS)/author0/%.csv
	./venue_author_preprocess.R $^ -o $@
features/$(DS)/item/%.csv: features/$(DS)/item0/%.csv
	./venue_author_preprocess.R $^ -o $@

features/$(DS)/c_org/%.h5: data/$(DS)/author/%.csv
	mkdir -p $(dir $@)
	./c_org.py $^ -o $@

features/$(DS)/c_keywords/%.h5: data/$(DS)/keywords/%.csv
	mkdir -p $(dir $@)
	./c_org.py $^ -o $@ --field keywords

features/$(DS)/label/%.h5: data/$(DS)/item/%.csv
	mkdir -p $(dir $@)
	./label.py $^ -o $@ --ref data/assignment_$(DS).json

define merge-tpl
features/$(DS)/$(1).h5: $$($(DS)_names:%=features/$(DS)/$(1)/%.h5)
	./merge.py $$^ -o $$@ --field $(1)
endef
$(foreach k,c_keywords c_org label,$(eval $(call merge-tpl,$(k))))

# Delete partial files when the processes are killed.
.DELETE_ON_ERROR:
# Keep intermediate files around
.SECONDARY:
