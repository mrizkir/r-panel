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
import { useAuthStore } from '../stores/auth'

const route = useRoute()
const authStore = useAuthStore()

const menuItems = computed(() => {
  const items = [
    {
      name: 'PHPFPM',
      title: 'PHP-FPM',
      icon: 'mdi-code-tags',
      to: { name: 'PHPFPM' }
    },
    {
      name: 'Nginx',
      title: 'Nginx',
      icon: 'mdi-server-network',
      to: { name: 'Nginx' }
    }
  ]
  
  // Add Users (R-Panel users) only for admin
  if (authStore.user?.role === 'admin') {
    items.push({
      name: 'Users',
      title: 'Users',
      icon: 'mdi-account-group',
      to: { name: 'Users' }
    })
  }
  
  return items
})

function isActiveRoute(routeName) {
  return route.name === routeName
}
</script>

