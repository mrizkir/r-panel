<template>
  <div>
    <v-row>
      <v-col cols="12">
        <h1 class="text-h4 mb-4">Profil Saya</h1>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12" md="8" lg="6">
        <v-card>
          <v-card-title>Informasi Akun</v-card-title>
          <v-card-text>
            <v-list>
              <v-list-item>
                <v-list-item-title>Username</v-list-item-title>
                <v-list-item-subtitle>{{ authStore.user?.username }}</v-list-item-subtitle>
              </v-list-item>
              <v-list-item>
                <v-list-item-title>Role</v-list-item-title>
                <v-list-item-subtitle>{{ authStore.user?.role }}</v-list-item-subtitle>
              </v-list-item>
            </v-list>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>

    <v-row>
      <v-col cols="12" md="8" lg="6">
        <v-card>
          <v-card-title>Ubah Password</v-card-title>
          <v-card-text>
            <v-form ref="form" v-model="valid">
              <v-text-field
                v-model="passwordForm.newPassword"
                label="Password Baru"
                type="password"
                :rules="[rules.required, rules.minLength]"
                prepend-inner-icon="mdi-lock-outline"
                variant="outlined"
                class="mb-3"
              />
              <v-text-field
                v-model="passwordForm.confirmPassword"
                label="Konfirmasi Password Baru"
                type="password"
                :rules="[rules.required, rules.passwordMatch]"
                prepend-inner-icon="mdi-lock-check"
                variant="outlined"
                class="mb-3"
              />
              <v-alert
                v-if="errorMessage"
                type="error"
                variant="tonal"
                class="mb-3"
              >
                {{ errorMessage }}
              </v-alert>
              <v-alert
                v-if="successMessage"
                type="success"
                variant="tonal"
                class="mb-3"
              >
                {{ successMessage }}
              </v-alert>
              <v-btn
                color="primary"
                :loading="loading"
                :disabled="!valid"
                @click="updatePassword"
              >
                <v-icon left>mdi-content-save</v-icon>
                Simpan Password
              </v-btn>
            </v-form>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import api from '../services/api'
import { useAuthStore } from '../stores/auth'

const authStore = useAuthStore()
const form = ref(null)
const valid = ref(false)
const loading = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

const passwordForm = ref({
  newPassword: '',
  confirmPassword: ''
})

const rules = {
  required: (value) => !!value || 'Field ini wajib diisi',
  minLength: (value) => (value && value.length >= 6) || 'Password minimal 6 karakter',
  passwordMatch: (value) => value === passwordForm.value.newPassword || 'Password tidak cocok'
}

async function updatePassword() {
  if (!form.value?.validate()) {
    return
  }

  if (passwordForm.value.newPassword !== passwordForm.value.confirmPassword) {
    errorMessage.value = 'Password baru dan konfirmasi password tidak cocok'
    return
  }

  loading.value = true
  errorMessage.value = ''
  successMessage.value = ''

  try {
    await api.post(`/users/${authStore.user.id}/password`, {
      password: passwordForm.value.newPassword
    })
    
    successMessage.value = 'Password berhasil diubah'
    passwordForm.value = {
      newPassword: '',
      confirmPassword: ''
    }
    form.value?.resetValidation()
  } catch (error) {
    errorMessage.value = error.response?.data?.error || 'Gagal mengubah password'
  } finally {
    loading.value = false
  }
}
</script>

