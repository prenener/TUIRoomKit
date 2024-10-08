<template>
  <div ref="tuiInputRef" :class="['tui-input', themeClass]">
    <input
      ref="inputRef"
      :value="value"
      :placeholder="placeholder"
      :disabled="disabled"
      maxlength="80"
      :type="type"
      :readonly="readonly"
      :style="{ paddingRight: hasSuffixIcon ? '40px' : '16px' }"
      @focus="focus"
      @blur="blur"
      @input="handleInput"
      @change="handleInput"
    />
    <div
      v-if="hasSuffixIcon"
      class="suffix-icon"
      @mousedown.prevent
      @click="handleSuffixIconClick"
    >
      <slot name="suffixIcon"></slot>
    </div>
    <div v-if="showResults" class="results tui-theme-white">
      <div
        v-for="(item, index) in searchResult"
        :key="index"
        class="results-item"
        @mousedown.prevent
        @click="handleResultItemClick(item)"
      >
        {{ item.label || item.value }}
        <slot name="searchResultItem" :data="item"></slot>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, useSlots, onMounted, onUnmounted } from 'vue';

const slots = useSlots();

interface Props {
  theme?: 'white' | 'black';
  value?: string;
  placeholder?: string;
  disabled?: boolean;
  type?: string;
  readonly?: boolean;
  search?: (data: string) => any;
  select?: (data: any) => any;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
  theme: 'white',
  value: '',
  placeholder: '',
  disabled: false,
  type: 'text',
});
const themeClass = computed(() =>
  props.theme ? `tui-theme-${props.theme}` : ''
);

const emit = defineEmits(['input', 'focus', 'blur']);

const tuiInputRef = ref<HTMLInputElement | null>(null);
const inputRef = ref<HTMLInputElement | null>(null);
const show = ref(false);

const blur = (event: any) => {
  const { value } = event.target;
  show.value = false;
  const trimmedValue = value.trimStart().trimEnd();
  if (value !== trimmedValue) {
    event.target.value = trimmedValue;
  }
  emit('blur', tuiInputRef.value);
};
const focus = () => {
  show.value = true;
  emit('focus', tuiInputRef.value);
};
const handleSuffixIconClick = () => {
  inputRef.value?.blur();
};

const closeOnOutsideClick = (event: any) => {
  if (!tuiInputRef.value?.contains(event.target)) {
    show.value = false;
  }
};

function handleResultItemClick(item: any) {
  inputRef.value?.blur();
  if (props.select) {
    props.select(item);
  }
}

onMounted(() => {
  window.addEventListener('click', closeOnOutsideClick);
});

onUnmounted(() => {
  window.removeEventListener('click', closeOnOutsideClick);
});

const searchResult = ref<any>([]);
function handleInput(event: any) {
  const { value } = event.target;
  const trimmedValue = value.trimStart();

  if (value !== trimmedValue) {
    event.target.value = trimmedValue;
  }

  emit('input', trimmedValue);
  if (props.search) {
    searchResult.value = props.search(event.target.value);
  }
}
const showResults = computed(
  () => searchResult.value && searchResult.value?.length !== 0 && show.value
);

const hasSuffixIcon = computed(() => !!slots.suffixIcon);
</script>

<style lang="scss" scoped>
.tui-input {
  position: relative;
  display: inline-block;
  height: 100%;
}

input {
  box-sizing: border-box;
  width: 100%;
  height: 100%;
  padding: 10px 0 10px 16px;
  font-size: 14px;
  color: var(--font-color-3);
  background-color: var(--background-color-7);
  border: 1px solid var(--border-color);
  border-radius: 8px;
}

input:focus {
  border-color: var(--active-color-1);
  outline: 0;
}

input:disabled {
  background-color: var(--background-color-9);
}

.suffix-icon {
  position: absolute;
  top: 50%;
  right: 12px;
  display: flex;
  align-items: center;
  transform: translateY(-50%);
}

.results {
  position: absolute;
  z-index: 2;
  width: 100%;
  max-height: 254px;
  padding: 7px 0;
  overflow: auto;
  background-color: var(--background-color-7);
  border: 1px solid var(--border-color);
  border-radius: 4px;

  &-item {
    display: flex;
    align-items: center;
    padding: 6px 15px;
    white-space: nowrap;
    cursor: pointer;
  }

  &-item:hover {
    color: var(--active-color-2);
    background-color: var(--hover-background-color-1);
  }
}
</style>
