<template>
  <v-list nav density="compact">
    <v-list-item
      v-for="item in menuItems"
      :key="item.name"
      :to="item.to"
      :prepend-icon="item.icon"
      :title="item.title"
      :active="isActiveRoute(item.name)"
    />
  </v-list>
</template>

<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()

const menuItems = computed(() => [
  {
    name: 'Logs',
    title: 'Logs',
    icon: 'mdi-text-box-outline',
    to: { name: 'Logs' }
  }
])

function isActiveRoute(routeName) {
  return route.name === routeName
}
</script>

