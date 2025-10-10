class AddEncryptedTextareaToResonances < ActiveRecord::Migration[8.0]
  def change
    add_column :resonances, :encrypted_textarea, :text
  end
end
