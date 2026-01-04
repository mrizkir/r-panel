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
    name: 'MySQL',
    title: 'MySQL',
    icon: 'mdi-database',
    to: { name: 'MySQL' }
  },
  {
    name: 'Backups',
    title: 'Backups',
    icon: 'mdi-backup-restore',
    to: { name: 'Backups' }
  }
])

function isActiveRoute(routeName) {
  return route.name === routeName
}
</script>

