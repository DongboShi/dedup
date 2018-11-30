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
data/%.score: data/%.json
	parallel python evaluate.py $^ --names {} ::: $($(DS)_names) > $@
data/%.pdf: data/%.score
	./pscore.R $^ -o $@ > $@.log

data/%.zip: data/%.json
	ln -sf $^ result.json
	zip -9 $@ result.json

data/$(DS)/author0/%.csv: data/$(DS)/csv_flag
	:
data/$(DS)/item0/%.csv: data/$(DS)/csv_flag
	:
data/$(DS)/abstract/%.csv: data/$(DS)/csv_flag
	:
data/$(DS)/keywords/%.csv: data/$(DS)/csv_flag
	:
data/$(DS)/csv_flag: data/pubs_$(DS).json
	mkdir -p $(dir $@){item0,author0,abstract,keywords}
	./data_transfer.R $^ -o $(dir $@)
	touch $@
data/$(DS)/dual/%.csv: data/$(DS)/author/%.csv
	mkdir -p $(dir $@)
	./dual_marry.py $^ -o $@

data/$(DS)/venue_idf.csv: $($(DS)_names:%=data/$(DS)/venue/%.csv)
	./IDF.py $^ -o $@ --field venue

# for word2vec
data/$(DS)/ia.csv: $($(DS)_names:%=data/$(DS)/item/%.csv) $($(DS)_names:%=data/$(DS)/abstract/%.csv)
	./combine-at.R $($(DS)_names:%=data/$(DS)/item/%.csv) --abstract $($(DS)_names:%=data/$(DS)/abstract/%.csv) -o $@

features/d2v_singlet.model: data/train/ia.csv
	python doc2vec.py -i $^ -o $@
features/d2v_doublet.model: data/train/ia.csv data/validate/ia.csv
	python doc2vec.py -i $^ -o $@
features/train/doc2vec_singlet_native/%.h5: data/train/item/%.csv features/d2v_singlet.model
	mkdir -p $(dir $@)
	python doc2vec_pair_native.py -i $< -o $@ -m $(word 2,$^) > $@.log
features/$(DS)/doc2vec_doublet_native/%.h5: data/$(DS)/item/%.csv features/d2v_doublet.model
	mkdir -p $(dir $@)
	python doc2vec_pair_native.py -i $< -o $@ -m $(word 2,$^) > $@.log

data/$(DS)/uniglue/%.csv: data/$(DS)/item/%.csv data/$(DS)/author/%.csv
	mkdir -p $(dir $@)
	./uni_glue_baseline.R $< --author $(word 2,$^) -o $@
data/$(DS)/coauthor/%.csv: data/$(DS)/author/%.csv
	mkdir -p $(dir $@)
	./coauthor_glue.R $< -o $@

data/uni_glue_${DS}.json: $($(DS)_names:%=data/$(DS)/uniglue/%.csv)
	./org_bag.py $^ -o $@ --field uniglue
data/coauthor_glue_${DS}.json: $($(DS)_names:%=data/$(DS)/coauthor/%.csv)
	./org_bag.py $^ -o $@ --field uniglue

data/$(DS)/author/%.csv: data/$(DS)/author0/%.csv
	mkdir -p $(dir $@)
	./venue_author_preprocess.R $^ -o $@ --field author

data/$(DS)/item/%.csv: data/$(DS)/item0/%.csv
	mkdir -p $(dir $@)
	./venue_author_preprocess.R $^ -o $@ --field item

data/${DS}/title/%.csv: data/$(DS)/item/%.csv
	mkdir -p $(dir $@)
	./wordlist.py $^ -o $@ --field title
data/${DS}/venue/%.csv: data/$(DS)/item/%.csv
	mkdir -p $(dir $@)
	./wordlist.py $^ -o $@ --field venue

features/$(DS)/shortpath/%.h5: data/$(DS)/author/%.csv
	mkdir -p $(dir $@)
	python ./shortpath_feature.py $< -o $@

#features/$(DS)/c_authorFN/%.h5: data/$(DS)/author/%.csv
#	mkdir -p $(dir $@)
#	./c_org.py $< -o $@ --field authorFN

features/$(DS)/c_org/%.h5: data/$(DS)/author/%.csv
	mkdir -p $(dir $@)
	./c_org.py $^ -o $@

features/$(DS)/c_title/%.h5: data/$(DS)/title/%.csv
	mkdir -p $(dir $@)
	./c_org.py $^ -o $@ --field title

features/$(DS)/c_venue/%.h5: data/$(DS)/venue/%.csv
	mkdir -p $(dir $@)
	./c_org.py $^ -o $@ --field venue

features/$(DS)/diff_year/%.h5: data/$(DS)/item/%.csv
	mkdir -p $(dir $@)
	./diff_year.py $^ -o $@ --field year

features/$(DS)/c_keywords/%.h5: data/$(DS)/keywords/%.csv
	mkdir -p $(dir $@)
	./c_org.py $^ -o $@ --field keywords

features/$(DS)/id_pairs/%.h5: data/$(DS)/keywords/%.csv
	mkdir -p $(dir $@)
	./id_pairs.py $^ -o $@ --field keywords

features/$(DS)/valid_index/%.h5: data/$(DS)/keywords/%.csv
	mkdir -p $(dir $@)
	./valid_index.py $^ -o $@ --field keywords

features/$(DS)/label/%.h5: data/$(DS)/item/%.csv
	mkdir -p $(dir $@)
	./label.py $^ -o $@ --ref data/assignment_$(DS).json

define merge-tpl
features/$(DS)/$(1).h5: $$($(DS)_names:%=features/$(DS)/$(1)/%.h5)
	./merge.py $$^ -o $$@ --field $(1)
endef

paired_features:=c_keywords c_org shortpath diff_year id_pairs valid_index c_title c_venue doc2vec_singlet_native doc2vec_doublet_native label

$(foreach k,$(paired_features),$(eval $(call merge-tpl,$(k))))

# Delete partial files when the processes are killed.
.DELETE_ON_ERROR:
# Keep intermediate files around
.SECONDARY:
