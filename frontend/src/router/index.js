import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('../views/Login.vue'),
    meta: { requiresAuth: false },
  },
  {
    path: '/',
    component: () => import('../components/Layout.vue'),
    meta: { requiresAuth: true },
    children: [
      {
        path: '',
        redirect: '/dashboard',
      },
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('../views/Dashboard.vue'),
      },
      {
        path: 'phpfpm',
        name: 'PHPFPM',
        component: () => import('../views/PHPFPM/List.vue'),
      },
      {
        path: 'nginx',
        name: 'Nginx',
        component: () => import('../views/Nginx/Sites.vue'),
      },
      {
        path: 'mysql',
        name: 'MySQL',
        component: () => import('../views/MySQL/Databases.vue'),
      },
      {
        path: 'backups',
        name: 'Backups',
        component: () => import('../views/Backups/Files.vue'),
      },
      {
        path: 'users',
        name: 'Users',
        component: () => import('../views/Users/List.vue'),
      },
      {
        path: 'logs',
        name: 'Logs',
        component: () => import('../views/Logs/Viewer.vue'),
      },
      {
        path: 'profile',
        name: 'Profile',
        component: () => import('../views/Profile.vue'),
      },
      {
        path: 'clients',
        name: 'ClientList',
        component: () => import('../views/ClientsList.vue'),
      },
    ],
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to, from, next) => {
  const authStore = useAuthStore()

  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    next('/login')
  } else if (to.path === '/login' && authStore.isAuthenticated) {
    next('/dashboard')
  } else {
    next()
  }
})

export default router

