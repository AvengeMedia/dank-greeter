package dank16

import "encoding/json"

func GenerateVariantJSON(p VariantPalette) string {
	marshalled, _ := json.Marshal(p)
	return string(marshalled)
}
