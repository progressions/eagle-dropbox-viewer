defmodule EagleDropboxViewer.Dropbox.TokenCrypto do
  @moduledoc false

  @aad "eagle-dropbox-viewer-token-v1"

  def encrypt(plaintext) when is_binary(plaintext) do
    key = key()
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)
    Base.encode64(iv <> tag <> ciphertext)
  end

  def decrypt(encoded) when is_binary(encoded) do
    key = key()

    case Base.decode64(encoded) do
      {:ok, <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>} ->
        case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
          plaintext when is_binary(plaintext) -> {:ok, plaintext}
          :error -> {:error, :decrypt_failed}
        end

      _ ->
        {:error, :invalid_ciphertext}
    end
  end

  defp key do
    secret =
      Application.get_env(:eagle_dropbox_viewer, EagleDropboxViewerWeb.Endpoint)[:secret_key_base] ||
        raise "SECRET_KEY_BASE / endpoint secret_key_base is required to encrypt Dropbox tokens"

    :crypto.hash(:sha256, secret)
  end
end
